package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/dougkusanagi/guepardo-fresh-os-config/catalog"
	"golang.org/x/term"
)

var profileOrder = []string{"cli", "dev", "web", "desktop", "games", "network"}
var themes = []string{"tokyo-night", "catppuccin", "nord", "everforest", "gruvbox", "kanagawa", "ristretto", "rose-pine", "matte-black", "osaka-jade"}
var sudoRefreshInterval = 25 * time.Second

func init() {
	c, err := catalog.Load()
	if err != nil {
		panic(err)
	}
	for _, p := range c.Profiles {
		if p.LinuxRecipe != "" {
			profileLabels[p.ID] = p.Label
		}
	}
}

var profileLabels = map[string]string{
	"cli":     "Ferramentas de terminal",
	"dev":     "Node, Bun, uv, Podman e ferramentas de desenvolvimento",
	"web":     "PHP, Composer e banco de dados",
	"desktop": "Aplicativos e ajustes do desktop",
	"games":   "Steam, Lutris e jogos",
	"network": "IPv4 estático (altera a conexão de rede)",
}

var presets = map[string]string{
	"all":     "cli,dev,web,desktop,games,network",
	"todos":   "cli,dev,web,desktop,games,network",
	"server":  "cli",
	"basic":   "cli,dev,web",
	"full":    "cli,dev,web,desktop,games",
	"games":   "games",
	"wsl":     "cli,dev,web",
	"dev-web": "dev,web",
}

type options struct {
	profiles         string
	mode             string
	distro           string
	root             string
	theme            string
	networkInterface string
	networkUUID      string
	networkAddress   string
	networkGateway   string
	networkDNS       string
	plan             bool
	dryRun           bool
	doctor           bool
	yes              bool
	list             bool
	listThemes       bool
	jobs             int
	resume           bool
	retryFailed      bool
	stateDir         string
}

func parseProfiles(input string) ([]string, error) {
	input = strings.ToLower(strings.TrimSpace(input))
	if alias, ok := presets[input]; ok {
		input = alias
	}
	if input == "" {
		return nil, errors.New("escolha ao menos um perfil")
	}
	selected := map[string]bool{}
	for _, raw := range strings.Split(input, ",") {
		name := strings.TrimSpace(raw)
		if alias, ok := presets[name]; ok {
			for _, nested := range strings.Split(alias, ",") {
				selected[nested] = true
			}
			continue
		}
		if _, ok := profileLabels[name]; !ok {
			return nil, fmt.Errorf("perfil desconhecido %q", name)
		}
		selected[name] = true
	}
	var result []string
	for _, name := range profileOrder {
		if selected[name] {
			result = append(result, name)
		}
	}
	return result, nil
}

func detectDistro(requested string) (string, error) {
	switch strings.ToLower(requested) {
	case "ubuntu", "debian":
		return "ubuntu", nil
	case "fedora", "nobara":
		return "fedora", nil
	case "auto":
	default:
		return "", fmt.Errorf("distribuição desconhecida: %s", requested)
	}
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "", err
	}
	fields := map[string]string{}
	for _, line := range strings.Split(string(data), "\n") {
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			fields[parts[0]] = strings.Trim(parts[1], "\"'")
		}
	}
	id, like := fields["ID"], fields["ID_LIKE"]
	if id == "ubuntu" || id == "debian" || strings.Contains(" "+like+" ", " debian ") {
		return "ubuntu", nil
	}
	if id == "fedora" || id == "nobara" || strings.Contains(" "+like+" ", " fedora ") {
		return "fedora", nil
	}
	return "", fmt.Errorf("distribuição não suportada: %s", id)
}

func hasProfile(profiles []string, name string) bool {
	for _, p := range profiles {
		if p == name {
			return true
		}
	}
	return false
}

func color(code, value string, enabled bool) string {
	if !enabled {
		return value
	}
	return "\x1b[" + code + "m" + value + "\x1b[0m"
}

// checkRunUser recusa root, exceto no WSL, onde o usuário padrão costuma ser root.
func checkRunUser(euid int, wsl bool) error {
	if euid == 0 && !wsl {
		return errors.New("execute como usuário normal, sem sudo")
	}
	return nil
}

func isWSLEnvironment() bool {
	if os.Getenv("WSL_DISTRO_NAME") != "" || os.Getenv("WSL_INTEROP") != "" {
		return true
	}
	data, _ := os.ReadFile("/proc/sys/kernel/osrelease")
	return strings.Contains(strings.ToLower(string(data)), "microsoft")
}

func promptProfiles() (string, error) {
	state, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		return "", fmt.Errorf("não consegui abrir o seletor interativo: %w", err)
	}
	defer term.Restore(int(os.Stdin.Fd()), state)
	fmt.Fprint(os.Stdout, "\x1b[?1049h\x1b[?25l")
	defer fmt.Fprint(os.Stdout, "\x1b[?25h\x1b[?1049l")
	picker := newProfilePickerForEnvironment(isWSLEnvironment())
	if width, height, err := term.GetSize(int(os.Stdout.Fd())); err == nil {
		if width < 40 || height < 20 {
			return "", errors.New("amplie o terminal para pelo menos 40 colunas e 20 linhas para abrir o menu")
		}
		picker.width, picker.height = width, height
	}
	return selectProfilesWithPicker(os.Stdin, crlfWriter{os.Stdout}, os.Getenv("NO_COLOR") == "", picker)
}

func confirmInstallation(input io.Reader, output io.Writer) (bool, error) {
	fmt.Fprint(output, "\nIniciar instalação? [S/n]: ")
	answer, err := bufio.NewReader(input).ReadString('\n')
	if errors.Is(err, io.EOF) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	answer = strings.ToLower(strings.TrimSpace(answer))
	return answer == "" || answer == "s", nil
}

func resolveRoot(explicit string) (string, error) {
	if explicit != "" {
		return filepath.Abs(explicit)
	}
	if env := os.Getenv("GUEPARDO_ROOT"); env != "" {
		return filepath.Abs(env)
	}
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "install-common", "lib.sh")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", errors.New("não encontrei o repositório; use --root=CAMINHO")
}

func logPath() (string, error) {
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		state = filepath.Join(home, ".local", "state")
	}
	dir := filepath.Join(state, "guepardo", "logs")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	return filepath.Join(dir, "install-"+time.Now().Format("20060102-150405")+fmt.Sprintf("-%d.log", os.Getpid())), nil
}

// sudoSession authenticates once and refreshes the timestamp while any profile runs.
// All child scripts call sudo -n, so a lost credential fails instead of hanging.
func sudoSession(ctx context.Context, cancel context.CancelFunc, log io.Writer) (func(), <-chan error, error) {
	initialArgs := []string{"-v"}
	if !isTerminal(os.Stdin) {
		if os.Getenv("SUDO_ASKPASS") != "" {
			initialArgs = []string{"-A", "-v"}
		} else {
			initialArgs = []string{"-n", "-v"}
		}
	}
	initial := exec.CommandContext(ctx, "sudo", initialArgs...)
	initial.Stdin, initial.Stdout, initial.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := initial.Run(); err != nil {
		return nil, nil, fmt.Errorf("não foi possível autenticar sudo: %w", err)
	}
	stop := make(chan struct{})
	done := make(chan struct{})
	failures := make(chan error, 1)
	go func() {
		defer close(done)
		ticker := time.NewTicker(sudoRefreshInterval)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ctx.Done():
				return
			case <-ticker.C:
				check, checkCancel := context.WithTimeout(ctx, 10*time.Second)
				cmd := exec.CommandContext(check, "sudo", "-n", "-v")
				output, err := cmd.CombinedOutput()
				checkCancel()
				if err != nil {
					failure := fmt.Errorf("a credencial sudo expirou: %w (%s)", err, strings.TrimSpace(string(output)))
					fmt.Fprintln(log, failure)
					failures <- failure
					cancel()
					return
				}
			}
		}
	}()
	var once sync.Once
	return func() { once.Do(func() { close(stop); <-done }) }, failures, nil
}

func runProfile(ctx context.Context, root, distro, profile, theme string, dryRun bool, jobs int, indexMarker string, network [5]string, interactive bool, output io.Writer, log io.Writer) error {
	c, catalogErr := catalog.Load()
	if catalogErr != nil {
		return catalogErr
	}
	recipe := ""
	for _, p := range c.Profiles {
		if p.ID == profile {
			recipe = p.LinuxRecipe
		}
	}
	if recipe == "" {
		return fmt.Errorf("perfil Linux desconhecido: %s", profile)
	}
	cmd := exec.CommandContext(ctx, "bash", filepath.Join(root, "scripts", "run-profile.sh"), distro, profile)
	configureProcessCancellation(cmd)
	cmd.Dir = root
	cmd.Stdin = os.Stdin
	failurePath := ""
	if indexMarker != "" {
		failurePath = indexMarker + ".failures"
	}
	cmd.Env = append(os.Environ(), "GUEPARDO_ROOT="+root, "GUEPARDO_SUDO_NONINTERACTIVE=1", "GUEPARDO_DRY_RUN="+fmt.Sprint(dryRun), "GUEPARDO_JOBS="+fmt.Sprint(jobs), "GUEPARDO_INDEX_MARKER="+indexMarker, "GUEPARDO_FAILURES_FILE="+failurePath, "SELECTED_THEME="+theme,
		"STATIC_NETWORK_INTERFACE="+network[0], "STATIC_NETWORK_ADDRESS="+network[1], "STATIC_NETWORK_GATEWAY="+network[2], "STATIC_NETWORK_DNS="+network[3], "STATIC_NETWORK_UUID="+network[4])
	cmd.Env = append(cmd.Env, "GUEPARDO_PROFILE_RECIPE="+recipe)
	if !interactive {
		cmd.Stdout = io.MultiWriter(output, log)
		cmd.Stderr = io.MultiWriter(output, log)
		return cmd.Run()
	}
	reader, writer := io.Pipe()
	cmd.Stdout, cmd.Stderr = writer, writer
	var mu sync.Mutex
	last := "Preparando etapa"
	readDone := make(chan struct{})
	go func() {
		defer close(readDone)
		defer reader.Close()
		scanner := bufio.NewScanner(reader)
		scanner.Buffer(make([]byte, 4096), 1024*1024)
		for scanner.Scan() {
			line := scanner.Text()
			fmt.Fprintln(log, line)
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			mu.Lock()
			switch {
			case strings.HasPrefix(line, "WARN"), strings.HasPrefix(line, "ERROR"):
				fmt.Fprintf(output, "\r\x1b[2K  %s\n", line)
			case strings.HasPrefix(line, "->"):
				last = strings.TrimSpace(strings.TrimPrefix(line, "->"))
			case strings.HasPrefix(line, "OK"):
				last = strings.TrimSpace(strings.TrimPrefix(line, "OK"))
			default:
				// Detailed package-manager output is kept in the log. The
				// terminal shows progress, warnings and explicit errors.
			}
			mu.Unlock()
		}
		if err := scanner.Err(); err != nil {
			fmt.Fprintln(log, "ERROR lendo saída do instalador:", err)
		}
	}()
	stopSpinner := make(chan struct{})
	spinnerDone := make(chan struct{})
	start := time.Now()
	go func() {
		defer close(spinnerDone)
		ticker := time.NewTicker(180 * time.Millisecond)
		defer ticker.Stop()
		frames := []string{"◐", "◓", "◑", "◒"}
		frame := 0
		for {
			select {
			case <-stopSpinner:
				return
			case <-ticker.C:
				mu.Lock()
				fmt.Fprintf(output, "\r\x1b[2K  %s %-72.72s %s", frames[frame%len(frames)], last, time.Since(start).Round(time.Second))
				mu.Unlock()
				frame++
			}
		}
	}()
	err := cmd.Run()
	writer.Close()
	<-readDone
	close(stopSpinner)
	<-spinnerDone
	fmt.Fprint(output, "\r\x1b[2K")
	return err
}

func run() error {
	var opts options
	flag.StringVar(&opts.profiles, "profiles", "", "perfis separados por vírgula: cli,dev,web,desktop,games,network")
	flag.StringVar(&opts.mode, "mode", "", "atalho legado: full,basic,games,wsl,server")
	flag.StringVar(&opts.distro, "distro", "auto", "auto,ubuntu,fedora,nobara")
	flag.StringVar(&opts.root, "root", "", "diretório do repositório")
	flag.StringVar(&opts.theme, "theme", "", "tema GNOME opcional")
	flag.StringVar(&opts.networkInterface, "network-interface", "", "interface de rede para o perfil network")
	flag.StringVar(&opts.networkAddress, "network-address", "", "IPv4/CIDR para o perfil network")
	flag.StringVar(&opts.networkGateway, "network-gateway", "", "gateway IPv4 para o perfil network")
	flag.StringVar(&opts.networkDNS, "network-dns", "", "DNS IPv4 para o perfil network")
	flag.BoolVar(&opts.plan, "plan", false, "mostrar plano e sair")
	flag.BoolVar(&opts.dryRun, "dry-run", false, "simular execução sem modificar o sistema")
	flag.BoolVar(&opts.doctor, "doctor", false, "verificar ferramentas e compatibilidade sem instalar")
	flag.BoolVar(&opts.yes, "yes", false, "executar sem confirmação final")
	flag.BoolVar(&opts.list, "list-profiles", false, "listar perfis")
	flag.BoolVar(&opts.listThemes, "list-themes", false, "listar temas GNOME")
	flag.IntVar(&opts.jobs, "jobs", 4, "limite de instaladores independentes simultâneos (1-8)")
	flag.BoolVar(&opts.resume, "resume", false, "retomar etapas concluídas após verificar os aplicativos")
	flag.BoolVar(&opts.retryFailed, "retry-failed", false, "repetir pendências e verificar resultados anteriores")
	flag.StringVar(&opts.stateDir, "state-dir", "", "diretório dos checkpoints por aplicativo")
	flag.Parse()
	// The Bash backends inherit recovery policy; dry-run never writes checkpoints.
	if opts.resume {
		os.Setenv("GUEPARDO_RESUME", "true")
	}
	if opts.retryFailed {
		os.Setenv("GUEPARDO_RETRY_FAILED", "true")
	}
	if opts.stateDir != "" {
		os.Setenv("GUEPARDO_STATE_DIR", opts.stateDir)
	}
	if flag.NArg() != 0 {
		return fmt.Errorf("argumentos desconhecidos: %s", strings.Join(flag.Args(), " "))
	}
	if opts.list {
		for _, p := range profileOrder {
			fmt.Printf("%-9s %s\n", p, profileLabels[p])
		}
		return nil
	}
	if opts.listThemes {
		fmt.Println(strings.Join(themes, "\n"))
		return nil
	}
	if opts.jobs < 1 || opts.jobs > 8 {
		return errors.New("--jobs deve estar entre 1 e 8")
	}
	if opts.profiles != "" && opts.mode != "" {
		return errors.New("use --profiles ou --mode, não ambos")
	}
	if opts.mode != "" {
		opts.profiles = opts.mode
	}
	interactive := isTerminal(os.Stdin) && isTerminal(os.Stdout)
	if opts.profiles == "" && opts.doctor {
		opts.profiles = "cli"
	}
	if opts.profiles == "" {
		if interactive && !opts.yes {
			var err error
			opts.profiles, err = promptProfiles()
			if err != nil {
				return err
			}
		} else {
			return errors.New("em modo não interativo informe --profiles=cli ou outro perfil")
		}
	}
	profiles, err := parseProfiles(opts.profiles)
	if err != nil {
		return err
	}
	if hasProfile(profiles, "network") {
		networks, _ := detectActiveNetworks()
		configureNetworkSettings(&opts, networks)
	}
	if opts.theme != "" && !hasProfile(profiles, "desktop") {
		return errors.New("--theme requer o perfil desktop")
	}
	if opts.theme != "" {
		valid := false
		for _, theme := range themes {
			valid = valid || opts.theme == theme
		}
		if !valid {
			return fmt.Errorf("tema desconhecido: %s", opts.theme)
		}
	}
	if hasProfile(profiles, "network") && !opts.plan && !opts.dryRun && !opts.doctor {
		if opts.networkInterface == "" || opts.networkAddress == "" || opts.networkGateway == "" {
			return errors.New("nenhuma rede ativa detectada; informe --network-interface")
		}
		address, _, err := net.ParseCIDR(opts.networkAddress)
		if err != nil || address.To4() == nil {
			return errors.New("--network-address deve ser um IPv4/CIDR válido")
		}
		if gateway := net.ParseIP(opts.networkGateway); gateway == nil || gateway.To4() == nil {
			return errors.New("--network-gateway deve ser um IPv4 válido")
		}
		if opts.networkDNS != "" {
			if dns := net.ParseIP(opts.networkDNS); dns == nil || dns.To4() == nil {
				return errors.New("--network-dns deve ser um IPv4 válido")
			}
		}
	}
	if runtime.GOOS != "linux" {
		return errors.New("este executável implementa Linux; no Windows use install.ps1")
	}
	distro, err := detectDistro(opts.distro)
	if err != nil {
		return err
	}
	root, err := resolveRoot(opts.root)
	if err != nil {
		return err
	}
	if opts.doctor || (!opts.plan && !opts.dryRun) {
		check := exec.Command("bash", filepath.Join(root, "scripts", "preflight.sh"), distro, strings.Join(profiles, ","), root)
		check.Stdout, check.Stderr = os.Stdout, os.Stderr
		if err := check.Run(); err != nil {
			return fmt.Errorf("a verificação inicial falhou; corrija os itens acima e execute novamente: %w", err)
		}
		if opts.doctor {
			return nil
		}
	}
	// Desktop finishes with dotagents after Claude and ChatGPT.
	os.Setenv("GUEPARDO_DEFER_DOTAGENTS", fmt.Sprint(hasProfile(profiles, "desktop")))
	colorEnabled := isTerminal(os.Stdout) && os.Getenv("NO_COLOR") == ""
	fmt.Println(color("1;36", "\n  GUEPARDO  /  fresh OS config", colorEnabled))
	fmt.Printf("  Sistema: %s   Perfis: %d   Downloads: até %d em paralelo\n\n", distro, len(profiles), opts.jobs)
	for i, name := range profiles {
		fmt.Printf("  %d/%d  %-9s %s\n", i+1, len(profiles), name, profileLabels[name])
	}
	if hasProfile(profiles, "network") {
		fmt.Println(color("1;33", "\n  Atenção: network altera a conexão IPv4 ativa.", colorEnabled))
		if opts.networkInterface != "" {
			fmt.Printf("  %s  %s  via %s  DNS %s\n", opts.networkInterface, opts.networkAddress, opts.networkGateway, opts.networkDNS)
		} else {
			fmt.Println("  IP fixo: 192.168.1.77/24 via 192.168.1.1, DNS 1.1.1.1 (interface detectada automaticamente).")
		}
	}
	if opts.plan {
		fmt.Println("\n  Ações previstas (sem alterações):")
		network := [5]string{opts.networkInterface, opts.networkAddress, opts.networkGateway, opts.networkDNS, opts.networkUUID}
		for _, profile := range profiles {
			fmt.Printf("\n  ▸ %s\n", profile)
			if err := runProfile(context.Background(), root, distro, profile, opts.theme, true, opts.jobs, "", network, false, os.Stdout, io.Discard); err != nil {
				return fmt.Errorf("não consegui montar o plano de %s: %w", profile, err)
			}
		}
		return nil
	}
	if err := checkRunUser(os.Geteuid(), isWSLEnvironment()); err != nil {
		return err
	}
	if !interactive && !opts.yes && !opts.dryRun {
		return errors.New("em modo não interativo use --yes para autorizar a instalação")
	}
	if interactive && !opts.yes && !opts.dryRun {
		confirmed, err := confirmInstallation(os.Stdin, os.Stdout)
		if err != nil {
			return err
		}
		if !confirmed {
			fmt.Println("Cancelado.")
			return nil
		}
	}
	path, err := logPath()
	if !opts.dryRun {
		stateDirectory := opts.stateDir
		if stateDirectory == "" {
			base := os.Getenv("XDG_STATE_HOME")
			if base == "" {
				home, homeErr := os.UserHomeDir()
				if homeErr != nil {
					return homeErr
				}
				base = filepath.Join(home, ".local", "state")
			}
			stateDirectory = filepath.Join(base, "guepardo", "steps")
		}
		unlock, lockErr := lockInstaller(stateDirectory)
		if lockErr != nil {
			return fmt.Errorf("outro instalador está ativo ou o diretório de estado não está acessível: %w", lockErr)
		}
		defer unlock()
	}
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	indexDir, err := os.MkdirTemp("", "guepardo-index-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(indexDir)
	indexMarker := filepath.Join(indexDir, "updated")
	fmt.Printf("\n  Log: %s\n", path)
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	var sudoFailures <-chan error
	if !opts.dryRun {
		fmt.Println("  Autenticando sudo uma vez para toda a instalação...")
		stop, failures, err := sudoSession(ctx, cancel, file)
		if err != nil {
			return err
		}
		defer stop()
		sudoFailures = failures
	}
	start := time.Now()
	var failedProfiles []string
	for i, profile := range profiles {
		fmt.Printf("\n%s\n", color("1;34", fmt.Sprintf("  [%d/%d] %s", i+1, len(profiles), profileLabels[profile]), colorEnabled))
		stepStart := time.Now()
		pendingBefore, _ := os.ReadFile(indexMarker + ".failures")
		network := [5]string{opts.networkInterface, opts.networkAddress, opts.networkGateway, opts.networkDNS, opts.networkUUID}
		if err := runProfile(ctx, root, distro, profile, opts.theme, opts.dryRun, opts.jobs, indexMarker, network, interactive, os.Stdout, file); err != nil {
			select {
			case authErr := <-sudoFailures:
				return fmt.Errorf("perfil %s interrompido: %w (log: %s)", profile, authErr, path)
			default:
			}
			if ctx.Err() != nil {
				return ctx.Err()
			}
			failure := fmt.Sprintf("perfil %s: %v", profile, err)
			failedProfiles = append(failedProfiles, failure)
			fmt.Fprintf(os.Stdout, "  WARN %s; continuando com os próximos perfis.\n", failure)
			fmt.Fprintln(file, failure)
			continue
		}
		pendingAfter, _ := os.ReadFile(indexMarker + ".failures")
		if len(pendingAfter) > len(pendingBefore) {
			fmt.Printf("  WARN %s finalizado com pendências em %s\n", profile, time.Since(stepStart).Round(time.Second))
		} else {
			fmt.Printf("  ✓ %s concluído em %s\n", profile, time.Since(stepStart).Round(time.Second))
		}
	}
	if appFailures, err := os.ReadFile(indexMarker + ".failures"); err == nil {
		for _, failure := range strings.Split(strings.TrimSpace(string(appFailures)), "\n") {
			if failure != "" {
				failedProfiles = append(failedProfiles, failure)
			}
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	if len(failedProfiles) > 0 {
		fmt.Println("\n  Instalação finalizada com pendências:")
		for _, failure := range failedProfiles {
			fmt.Printf("  - %s\n", failure)
			fmt.Fprintln(file, "Pendente:", failure)
		}
		return fmt.Errorf("%d pendência(s); os demais itens foram processados (log: %s). Corrija e repita o mesmo comando", len(failedProfiles), path)
	}
	fmt.Printf("\n%s %s  •  %s\n", color("1;32", "  Instalação concluída", colorEnabled), time.Since(start).Round(time.Second), path)
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "Erro:", err)
		os.Exit(1)
	}
}
