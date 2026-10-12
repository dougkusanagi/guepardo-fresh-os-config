package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf16"

	assets "github.com/dougkusanagi/guepardo-fresh-os-config"
	"golang.org/x/term"
)

type windowsApp struct {
	id   string
	name string
}

type windowsPackageManager string

const (
	windowsPackageManagerWinget windowsPackageManager = "winget"
	windowsPackageManagerScoop  windowsPackageManager = "scoop"
)

var windowsPackageManagersByID = map[string]windowsPackageManager{
	"wget":  windowsPackageManagerScoop,
	"unzip": windowsPackageManagerScoop,
}

var windowsAppsByProfile = map[string][]windowsApp{
	"cli": {
		{"GitHub.cli", "GitHub CLI"},
		{"Git.Git", "Git"},
		{"sharkdp.bat", "bat"},
		{"Clement.bottom", "bottom"},
		{"sharkdp.fd", "fd"},
		{"junegunn.fzf", "fzf"},
		{"BurntSushi.ripgrep.MSVC", "ripgrep"},
		{"chmln.sd", "sd"},
		{"dbrgn.tealdeer", "tealdeer"},
		{"jqlang.jq", "jq"},
		{"eza-community.eza", "eza"},
		{"bootandy.dust", "dust"},
		{"JesseDuffield.lazygit", "lazygit"},
		{"sxyazi.yazi", "yazi"},
		{"GnuPG.Gpg4win", "GnuPG"},
		{"wget", "wget"},
		{"unzip", "unzip"},
	},
	"dev": {
		{"Oven-sh.Bun", "Bun"},
		{"astral-sh.uv", "uv"},
		{"CoreyButler.NVMforWindows", "NVM for Windows"},
		{"OpenAI.Codex", "Codex CLI"},
		{"SST.opencode", "OpenCode CLI"},
		{"Google.AntigravityCLI", "Antigravity CLI"},
		{"ZedIndustries.Zed", "Zed Editor"},
		{"GitHub.GitHubDesktop", "GitHub Desktop"},
		{"Termius.Termius", "Termius"},
		{"T3Tools.T3Code", "T3 Code"},
		{"GodotEngine.GodotEngine", "Godot Engine"},
		{"Comfy.ComfyUI-Desktop", "ComfyUI Desktop"},
		{"ElementLabs.Bionic", "Bionic"},
	},
	"web": {
		{"PHP.PHP.8.4", "PHP"},
		{"Composer.Composer", "Composer"},
		{"Oracle.MySQL", "MySQL Server"},
	},
	"desktop": {
		{"Warp.Warp", "Warp Terminal"},
		{"Microsoft.VisualStudioCode", "Visual Studio Code"},
		{"Skillbrains.Lightshot", "Lightshot"},
		{"RevoUninstaller.RevoUninstaller", "Revo Uninstaller"},
		{"Brave.Brave", "Brave Browser"},
		{"Google.Chrome", "Google Chrome"},
		{"Obsidian.Obsidian", "Obsidian"},
		{"OBSProject.OBSStudio", "OBS Studio"},
		{"ElementLabs.LMStudio", "LM Studio"},
		{"RARLab.WinRAR", "WinRAR"},
		{"Zen-Team.Zen-Browser", "Zen Browser"},
		{"dynobo.NormCap", "NormCap"},
		{"RedHat.Podman-Desktop", "Podman Desktop"},
		{"VideoLAN.VLC", "VLC Media Player"},
		{"CodecGuide.K-LiteCodecPack.Mega", "K-Lite Codec Pack Mega"},
		{"7zip.7zip", "7-Zip"},
		{"Microsoft.PowerToys", "PowerToys"},
		{"Anthropic.Claude", "Claude"},
		{"Telegram.TelegramDesktop", "Telegram Desktop"},
		{"Gyan.FFmpeg", "FFmpeg"},
		{"Canva.Affinity", "Affinity"},
	},
	"games": {
		{"Valve.Steam", "Steam"},
		{"EpicGames.EpicGamesLauncher", "Epic Games Launcher"},
		{"GOG.Galaxy", "GOG Galaxy"},
		{"Discord.Discord", "Discord"},
		{"qBittorrent.qBittorrent", "qBittorrent"},
		{"Stremio.Stremio", "Stremio"},
		{"HeroicGamesLauncher.HeroicGamesLauncher", "Heroic Games Launcher"},
	},
	"jellyfin": {
		{"Jellyfin.Server", "Jellyfin Server"},
	},
	"wsl2": {},
}

var windowsPresets = map[string]string{
	"all":      "cli,dev,web,desktop,games,jellyfin,wsl2",
	"todos":    "cli,dev,web,desktop,games,jellyfin,wsl2",
	"full":     "cli,dev,web,desktop,games,jellyfin,wsl2",
	"basic":    "cli,dev,web",
	"wsl":      "cli,dev,web,wsl2",
	"server":   "cli",
	"games":    "games",
	"desktop":  "desktop",
	"jellyfin": "jellyfin",
}

func parseWindowsProfiles(input string) ([]string, error) {
	input = strings.ToLower(strings.TrimSpace(input))
	if preset, ok := windowsPresets[input]; ok {
		input = preset
	}
	if input == "" {
		return nil, errors.New("escolha ao menos um perfil do Windows")
	}
	selected := make(map[string]bool)
	for _, raw := range strings.Split(input, ",") {
		name := strings.TrimSpace(raw)
		if preset, ok := windowsPresets[name]; ok {
			for _, nested := range strings.Split(preset, ",") {
				selected[nested] = true
			}
			continue
		}
		if _, ok := windowsAppsByProfile[name]; !ok {
			return nil, fmt.Errorf("perfil do Windows desconhecido %q", name)
		}
		selected[name] = true
	}
	var profiles []string
	for _, name := range windowsProfileOrder {
		if selected[name] {
			profiles = append(profiles, name)
		}
	}
	return profiles, nil
}

func windowsPackages(profiles []string) []windowsApp {
	seen := make(map[string]bool)
	var packages []windowsApp
	for _, profile := range windowsProfileOrder {
		if !hasProfile(profiles, profile) {
			continue
		}
		for _, app := range windowsAppsByProfile[profile] {
			if !seen[app.id] {
				seen[app.id] = true
				packages = append(packages, app)
			}
		}
	}
	return packages
}

func windowsWingetArgs(packageID string) []string {
	return []string{"install", "-e", "--id", packageID, "--source", "winget", "--silent", "--disable-interactivity", "--no-upgrade", "--accept-package-agreements", "--accept-source-agreements"}
}

func windowsPackageManagerFor(app windowsApp) windowsPackageManager {
	if manager, ok := windowsPackageManagersByID[app.id]; ok {
		return manager
	}
	return windowsPackageManagerWinget
}

func windowsScoopPowerShellScript(packageID string) string {
	packageID = strings.ReplaceAll(packageID, "'", "''")
	return fmt.Sprintf(`$ErrorActionPreference = 'Stop'
$scoopRoot = [System.Environment]::GetEnvironmentVariable('SCOOP', 'User')
if (-not $scoopRoot) { $scoopRoot = [System.Environment]::GetEnvironmentVariable('SCOOP', 'Machine') }
if (-not $scoopRoot) { $scoopRoot = Join-Path $env:USERPROFILE 'scoop' }
$scoopScript = Join-Path $scoopRoot 'apps\scoop\current\bin\scoop.ps1'
if (-not (Test-Path $scoopScript)) {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    $scoopRoot = [System.Environment]::GetEnvironmentVariable('SCOOP', 'User')
    if (-not $scoopRoot) { $scoopRoot = [System.Environment]::GetEnvironmentVariable('SCOOP', 'Machine') }
    if (-not $scoopRoot) { $scoopRoot = Join-Path $env:USERPROFILE 'scoop' }
    $scoopScript = Join-Path $scoopRoot 'apps\scoop\current\bin\scoop.ps1'
}
if (-not (Test-Path $scoopScript)) { throw 'Scoop foi instalado, mas scoop.ps1 não foi encontrado.' }
& $scoopScript install '%s'
`, packageID)
}

func windowsScoopPowerShellArgs(packageID string) []string {
	script := windowsScoopPowerShellScript(packageID)
	encoded := base64.StdEncoding.EncodeToString(utf16LE(script))
	return []string{"-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded}
}

func utf16LE(value string) []byte {
	encoded := utf16.Encode([]rune(value))
	data := make([]byte, len(encoded)*2)
	for index, unit := range encoded {
		binary.LittleEndian.PutUint16(data[index*2:], unit)
	}
	return data
}

func windowsPackagesNeedManager(packages []windowsApp, manager windowsPackageManager) bool {
	for _, app := range packages {
		if windowsPackageManagerFor(app) == manager {
			return true
		}
	}
	return false
}

func classifyWindowsWSLExitCode(exitCode int) string {
	switch exitCode {
	case 0:
		return "configured"
	case 3010:
		return "reboot-required"
	default:
		return "failed"
	}
}

func classifyWingetExitCode(exitCode int) string {
	switch uint32(exitCode) {
	case 0:
		return "installed"
	case 0x8A15002B, 0x8A150061, 0x8A15010D:
		return "already-installed"
	case 0x8A150109, 3010:
		return "reboot-required"
	default:
		return "failed"
	}
}

func promptWindowsProfiles() (string, error) {
	state, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		return "", fmt.Errorf("não consegui abrir o seletor do Windows: %w", err)
	}
	defer term.Restore(int(os.Stdin.Fd()), state)
	fmt.Fprint(os.Stdout, "\x1b[?1049h\x1b[?25l")
	defer fmt.Fprint(os.Stdout, "\x1b[?25h\x1b[?1049l")
	picker := newProfilePicker()
	picker.windows = true
	if width, height, err := term.GetSize(int(os.Stdout.Fd())); err == nil {
		if width < 40 || height < 20 {
			return "", errors.New("amplie o terminal para pelo menos 40 colunas e 20 linhas para abrir o menu")
		}
		picker.width, picker.height = width, height
	}
	return selectProfilesWithPicker(os.Stdin, crlfWriter{os.Stdout}, os.Getenv("NO_COLOR") == "", picker)
}

func printWindowsProfiles(output io.Writer) {
	for _, profile := range windowsProfileOrder {
		fmt.Fprintf(output, "%-9s %s\n", profile, windowsProfileLabels[profile])
	}
}

func runWindows(opts options) error {
	if opts.list {
		printWindowsProfiles(os.Stdout)
		return nil
	}
	if opts.listThemes {
		return errors.New("temas GNOME estão disponíveis somente no Linux")
	}
	if opts.profiles != "" && opts.mode != "" {
		return errors.New("use --profiles ou --mode, não ambos")
	}
	if opts.theme != "" || opts.distro != "auto" || opts.networkInterface != "" || opts.networkAddress != "" || opts.networkGateway != "" || opts.networkDNS != "" {
		return errors.New("opções de Linux não se aplicam ao instalador Windows")
	}
	profilesInput := opts.profiles
	if opts.mode != "" {
		profilesInput = opts.mode
	}
	interactive := isTerminal(os.Stdin) && isTerminal(os.Stdout)
	if profilesInput == "" && opts.doctor {
		profilesInput = "cli"
	}
	if profilesInput == "" {
		if interactive && !opts.yes {
			var err error
			profilesInput, err = promptWindowsProfiles()
			if err != nil {
				return err
			}
		} else {
			return errors.New("em modo não interativo informe --profiles=cli ou outro perfil do Windows")
		}
	}
	profiles, err := parseWindowsProfiles(profilesInput)
	if err != nil {
		return err
	}
	root, rootErr := resolveRoot(opts.root)
	var cleanupAssets func()
	if rootErr != nil {
		if opts.root != "" || os.Getenv("GUEPARDO_ROOT") != "" {
			return rootErr
		}
		root = ""
	}
	if hasProfile(profiles, "jellyfin") && root == "" {
		var err error
		root, cleanupAssets, err = materializeEmbeddedWindowsAssets()
		if err != nil {
			return err
		}
		defer cleanupAssets()
	}
	packages := windowsPackages(profiles)
	if opts.doctor {
		if windowsPackagesNeedManager(packages, windowsPackageManagerWinget) {
			if _, err := exec.LookPath("winget"); err != nil {
				return errors.New("Winget não encontrado. Instale o App Installer da Microsoft Store.")
			}
		}
		if hasProfile(profiles, "jellyfin") {
			if _, err := os.Stat(filepath.Join(root, "modules", "jellyfin.ps1")); err != nil {
				return fmt.Errorf("módulo Jellyfin ausente no repositório: %w", err)
			}
		}
		if hasProfile(profiles, "wsl2") {
			if _, err := exec.LookPath("wsl.exe"); err != nil {
				return errors.New("WSL não encontrado; atualize para Windows 10 build 19041 ou Windows 11")
			}
		}
		if windowsPackagesNeedManager(packages, windowsPackageManagerScoop) {
			fmt.Fprintln(os.Stdout, "Windows compatível; Winget está disponível e Scoop será instalado se necessário.")
		} else {
			fmt.Fprintln(os.Stdout, "Windows compatível; Winget e arquivos selecionados estão disponíveis.")
		}
		return nil
	}
	if opts.plan || opts.dryRun {
		printWindowsPlan(os.Stdout, profiles, packages)
		return nil
	}
	if !interactive && !opts.yes {
		return errors.New("em modo não interativo use --yes para autorizar a instalação")
	}
	if windowsPackagesNeedManager(packages, windowsPackageManagerWinget) {
		if _, err := exec.LookPath("winget"); err != nil {
			return errors.New("Winget não encontrado. Instale o App Installer da Microsoft Store.")
		}
	}
	if hasProfile(profiles, "wsl2") {
		if _, err := exec.LookPath("wsl.exe"); err != nil {
			return errors.New("WSL não encontrado; atualize para Windows 10 build 19041 ou Windows 11")
		}
	}
	if interactive && !opts.yes {
		printWindowsPlan(os.Stdout, profiles, packages)
		fmt.Fprint(os.Stdout, "\nIniciar instalação? [s/N]: ")
		answer, err := bufio.NewReader(os.Stdin).ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		if strings.ToLower(strings.TrimSpace(answer)) != "s" {
			fmt.Fprintln(os.Stdout, "Cancelado.")
			return nil
		}
	}
	path, err := logPath()
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	fmt.Fprintf(os.Stdout, "\n  Log: %s\n", path)
	fmt.Fprintf(file, "Perfis: %s\n", strings.Join(profiles, ","))
	ctx, stop := newSignalContext()
	defer stop()
	failed := make([]string, 0)
	jellyfinResult := "not-selected"
	started := time.Now()
	for index, app := range packages {
		manager := windowsPackageManagerFor(app)
		fmt.Fprintf(os.Stdout, "\n  [%d/%d] %s (%s: %s)\n", index+1, len(packages), app.name, manager, app.id)
		exitCode, runErr := runWindowsPackage(ctx, app, interactive, os.Stdout, file)
		result := "failed"
		if manager == windowsPackageManagerWinget {
			result = classifyWingetExitCode(exitCode)
		} else if exitCode == 0 {
			result = "installed"
		}
		if runErr != nil && exitCode == 0 {
			result = "failed"
		}
		if app.id == "Jellyfin.Server" {
			jellyfinResult = result
		}
		switch result {
		case "installed", "already-installed":
			fmt.Fprintf(os.Stdout, "  ✓ %s instalado ou já estava instalado.\n", app.name)
		case "reboot-required":
			fmt.Fprintf(os.Stdout, "  ! %s solicita reinicialização.\n", app.name)
		case "failed":
			fmt.Fprintf(os.Stdout, "  ! Falha ao instalar %s (código %d).\n", app.name, exitCode)
			failed = append(failed, app.name)
		}
		if runErr != nil {
			fmt.Fprintf(file, "Falha ao executar %s para %s: %v\n", manager, app.name, runErr)
		}
	}
	if hasProfile(profiles, "dev") {
		fmt.Fprintln(os.Stdout, "\n  Configurando Node.js LTS via NVM for Windows...")
		if err := installWindowsNodeLTS(ctx, interactive, os.Stdout, file); err != nil {
			fmt.Fprintf(os.Stdout, "  ! Falha ao configurar Node.js LTS: %v\n", err)
			fmt.Fprintf(file, "Falha ao configurar Node.js LTS: %v\n", err)
			failed = append(failed, "Node.js LTS via NVM")
		} else {
			fmt.Fprintln(os.Stdout, "  ✓ Node.js LTS e npm estão disponíveis.")
		}
	}
	if hasProfile(profiles, "wsl2") {
		fmt.Fprintln(os.Stdout, "\n  Instalando e atualizando WSL 2 + Ubuntu; o Windows solicitará elevação via UAC...")
		exitCode, runErr := installWindowsWSL(ctx, interactive, os.Stdout, file)
		if runErr != nil && exitCode == 0 {
			exitCode = 1
		}
		switch classifyWindowsWSLExitCode(exitCode) {
		case "configured":
			fmt.Fprintln(os.Stdout, "  ✓ WSL 2 e Ubuntu configurados. Se solicitado, reinicie o Windows; depois abra `wsl -d Ubuntu` para criar seu usuário Linux.")
		case "reboot-required":
			fmt.Fprintln(os.Stdout, "  ! Reinicie o Windows e execute novamente `guepardo.exe --profiles=wsl2 --yes` para concluir o WSL. Depois abra `wsl -d Ubuntu` para criar seu usuário Linux.")
		case "failed":
			fmt.Fprintf(os.Stdout, "  ! Falha ao configurar WSL 2 + Ubuntu (código %d).\n", exitCode)
			failed = append(failed, "WSL 2 + Ubuntu")
		}
		if runErr != nil {
			fmt.Fprintf(file, "Falha ao configurar WSL 2 + Ubuntu: %v\n", runErr)
		}
	}
	if hasProfile(profiles, "jellyfin") {
		switch jellyfinResult {
		case "installed", "already-installed":
			fmt.Fprintln(os.Stdout, "\n  Configurando tema e plugins do Jellyfin...")
			if err := runJellyfinConfiguration(ctx, root, os.Stdout, file); err != nil {
				fmt.Fprintf(os.Stdout, "  ! Configuração Jellyfin falhou: %v\n", err)
				failed = append(failed, "configuração Jellyfin")
			} else {
				fmt.Fprintln(os.Stdout, "  ✓ Tema e plugins Jellyfin configurados.")
			}
		case "reboot-required":
			fmt.Fprintln(os.Stdout, "\n  Reinicie o Windows e execute novamente --profiles=jellyfin para configurar o Jellyfin.")
			failed = append(failed, "configuração Jellyfin (reinicialização pendente)")
		default:
			fmt.Fprintln(os.Stdout, "\n  Configuração Jellyfin ignorada porque o servidor não foi instalado.")
		}
	}
	if hasProfile(profiles, "cli") || hasProfile(profiles, "dev") || hasProfile(profiles, "web") {
		if err := configureWindowsPowerShellProfile(profiles); err != nil {
			fmt.Fprintf(os.Stdout, "  ! Não foi possível atualizar o perfil PowerShell: %v\n", err)
			fmt.Fprintf(file, "Falha ao atualizar perfil PowerShell: %v\n", err)
			failed = append(failed, "perfil PowerShell")
		}
	}
	fmt.Fprintf(os.Stdout, "\n  Concluído em %s. Log: %s\n", time.Since(started).Round(time.Second), path)
	if len(failed) > 0 {
		fmt.Fprintf(os.Stdout, "  Falhas: %s\n", strings.Join(failed, ", "))
		return errors.New("instalação concluída com falhas; corrija os itens listados e execute os mesmos perfis novamente")
	}
	fmt.Fprintln(os.Stdout, "  Todos os grupos solicitados foram concluídos.")
	return nil
}

func printWindowsPlan(output io.Writer, profiles []string, packages []windowsApp) {
	fmt.Fprintln(output, "\n  GUEPARDO  /  fresh OS config")
	fmt.Fprintf(output, "  Sistema: Windows   Perfis: %d\n", len(profiles))
	for _, profile := range profiles {
		fmt.Fprintf(output, "\n  ▸ %s  %s\n", profile, windowsProfileLabels[profile])
	}
	fmt.Fprintln(output, "\n  Aplicativos previstos:")
	for _, app := range packages {
		fmt.Fprintf(output, "  • %s (%s: %s)\n", app.name, windowsPackageManagerFor(app), app.id)
	}
	if hasProfile(profiles, "dev") {
		fmt.Fprintln(output, "  • Node.js LTS e npm via NVM for Windows")
	}
	if hasProfile(profiles, "jellyfin") {
		fmt.Fprintln(output, "  • Jellyfin: aplicar GlassFin, instalar plugins e preservar backup do CSS anterior.")
	}
	if hasProfile(profiles, "wsl2") {
		fmt.Fprintln(output, "  • WSL: habilitar WSL e Virtual Machine Platform, atualizar o WSL e instalar a distribuição Ubuntu padrão mais recente.")
		fmt.Fprintln(output, "    A função completa do Hyper-V não é necessária; a instalação pede UAC e pode pedir reinicialização.")
		fmt.Fprintln(output, "    A virtualização Intel VT-x/AMD-V precisa estar habilitada no firmware UEFI/BIOS.")
	}
	fmt.Fprintln(output, "\n  Nenhum aplicativo ou configuração foi alterado.")
}

func runWingetPackage(ctx context.Context, app windowsApp, interactive bool, output io.Writer, log io.Writer) (int, error) {
	cmd := exec.CommandContext(ctx, "winget", windowsWingetArgs(app.id)...)
	return runPackageCommand(ctx, cmd, app.name, "Winget", interactive, output, log)
}

func runScoopPackage(ctx context.Context, app windowsApp, interactive bool, output io.Writer, log io.Writer) (int, error) {
	cmd := exec.CommandContext(ctx, "powershell.exe", windowsScoopPowerShellArgs(app.id)...)
	return runPackageCommand(ctx, cmd, app.name, "Scoop", interactive, output, log)
}

func runWindowsPackage(ctx context.Context, app windowsApp, interactive bool, output io.Writer, log io.Writer) (int, error) {
	if windowsPackageManagerFor(app) == windowsPackageManagerScoop {
		return runScoopPackage(ctx, app, interactive, output, log)
	}
	return runWingetPackage(ctx, app, interactive, output, log)
}

func runPackageCommand(ctx context.Context, cmd *exec.Cmd, appName, manager string, interactive bool, output io.Writer, log io.Writer) (int, error) {
	cmd.Stdout, cmd.Stderr = log, log
	if !interactive {
		err := cmd.Run()
		return windowsCommandExitCode(err), err
	}
	if err := cmd.Start(); err != nil {
		return 1, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	frames := []string{"◐", "◓", "◑", "◒"}
	ticker := time.NewTicker(180 * time.Millisecond)
	defer ticker.Stop()
	frame := 0
	for {
		select {
		case err := <-done:
			fmt.Fprint(output, "\r\x1b[2K")
			return windowsCommandExitCode(err), err
		case <-ctx.Done():
			if err := <-done; err != nil {
				fmt.Fprint(output, "\r\x1b[2K")
				return windowsCommandExitCode(err), err
			}
			fmt.Fprint(output, "\r\x1b[2K")
			return 1, ctx.Err()
		case <-ticker.C:
			fmt.Fprintf(output, "\r\x1b[2K  %s Instalando %s via %s...", frames[frame%len(frames)], appName, manager)
			frame++
		}
	}
}

func windowsWSLAdminPowerShellScript() string {
	return `$ErrorActionPreference = 'Stop'
$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $wsl)) {
    Write-Error 'wsl.exe não foi encontrado. Atualize para Windows 10 build 19041 ou Windows 11.'
    exit 1
}
$restartNeeded = $false
foreach ($featureName in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    $featureResult = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
    if ($featureResult.RestartNeeded) { $restartNeeded = $true }
}
if ($restartNeeded) {
    Write-Output 'Os recursos necessários para WSL 2 foram habilitados e aguardam reinicialização.'
    exit 3010
}
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$installedDistros = @(& $wsl --list --quiet 2>$null | ForEach-Object {
    $name = ([string]$_).Replace([string][char]0, '').Trim()
    if ($name) { $name }
})
$listExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($listExitCode -ne 0) { $installedDistros = @() }
if ($installedDistros -notcontains 'Ubuntu') {
    & $wsl --install --distribution Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $wsl --update
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $wsl --set-default-version 2
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $wsl --set-version Ubuntu 2
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $wsl --set-default Ubuntu
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'WSL atualizado; Ubuntu instalado e definido como distribuição padrão.'
exit 0
`
}

func windowsWSLPowerShellScript() string {
	encodedAdminScript := base64.StdEncoding.EncodeToString(utf16LE(windowsWSLAdminPowerShellScript()))
	return fmt.Sprintf(`$ErrorActionPreference = 'Stop'
$payload = '%s'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $script = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($payload))
    Invoke-Expression $script
    exit $LASTEXITCODE
}
Write-Output 'Solicitando elevação do Windows para instalar recursos do WSL.'
$arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $payload
$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
exit $process.ExitCode
`, encodedAdminScript)
}

func installWindowsWSL(ctx context.Context, interactive bool, output io.Writer, log io.Writer) (int, error) {
	encoded := base64.StdEncoding.EncodeToString(utf16LE(windowsWSLPowerShellScript()))
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded)
	return runPackageCommand(ctx, cmd, "WSL 2 + Ubuntu", "Windows", interactive, output, log)
}

func windowsNodeLTSPowerShellScript() string {
	return `$ErrorActionPreference = 'Stop'
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath"
$node = Get-Command node.exe -ErrorAction SilentlyContinue
$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($node -and $npm) {
    $version = (& $node.Source --version).Trim()
    if ($version -match '^v(22|24)\.') { exit 0 }
}
$nvmPath = (Get-Command nvm.exe -ErrorAction SilentlyContinue).Source
if (-not $nvmPath) {
    $nvmHome = [System.Environment]::GetEnvironmentVariable('NVM_HOME', 'User')
    if (-not $nvmHome) { $nvmHome = [System.Environment]::GetEnvironmentVariable('NVM_HOME', 'Machine') }
    if ($nvmHome -and (Test-Path (Join-Path $nvmHome 'nvm.exe'))) {
        $nvmPath = Join-Path $nvmHome 'nvm.exe'
    }
}
if (-not $nvmPath) { throw 'NVM for Windows não foi encontrado após a instalação.' }
& $nvmPath install lts
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $nvmPath use lts
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -or -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw 'NVM terminou sem disponibilizar node.exe e npm.cmd no PATH.'
}
`
}

func installWindowsNodeLTS(ctx context.Context, interactive bool, output io.Writer, log io.Writer) error {
	encoded := base64.StdEncoding.EncodeToString(utf16LE(windowsNodeLTSPowerShellScript()))
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded)
	_, err := runPackageCommand(ctx, cmd, "Node.js LTS", "NVM for Windows", interactive, output, log)
	return err
}

func windowsCommandExitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return 1
}

func runJellyfinConfiguration(ctx context.Context, root string, output io.Writer, log io.Writer) error {
	module := filepath.Join(root, "modules", "jellyfin.ps1")
	if _, err := os.Stat(module); err != nil {
		return fmt.Errorf("módulo Jellyfin não encontrado: %w", err)
	}
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", module, "-SkipInstall")
	cmd.Dir = root
	cmd.Stdin = os.Stdin
	cmd.Stdout = io.MultiWriter(output, log)
	cmd.Stderr = io.MultiWriter(output, log)
	return cmd.Run()
}

func materializeEmbeddedWindowsAssets() (string, func(), error) {
	root, err := os.MkdirTemp("", "guepardo-windows-assets-")
	if err != nil {
		return "", nil, err
	}
	cleanup := func() { _ = os.RemoveAll(root) }
	for _, name := range []string{"modules/jellyfin.ps1", "jellyfin/polish.css"} {
		data, err := fs.ReadFile(assets.WindowsFiles, name)
		if err != nil {
			cleanup()
			return "", nil, fmt.Errorf("não consegui carregar o recurso Windows %s: %w", name, err)
		}
		destination := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
			cleanup()
			return "", nil, err
		}
		if err := os.WriteFile(destination, data, 0600); err != nil {
			cleanup()
			return "", nil, err
		}
	}
	return root, cleanup, nil
}

func configureWindowsPowerShellProfile(profiles []string) error {
	home := os.Getenv("USERPROFILE")
	if home == "" {
		var err error
		home, err = os.UserHomeDir()
		if err != nil {
			return err
		}
	}
	profilePaths := []string{
		filepath.Join(home, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"),
		filepath.Join(home, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1"),
	}
	blocks := []struct {
		profile string
		marker  string
		text    string
	}{
		{"cli", "# region Guepardo Fresh OS Config Shortcuts", `# region Guepardo Fresh OS Config Shortcuts
function refreshenv {
    $userEnv = [System.Environment]::GetEnvironmentVariables("User")
    $machineEnv = [System.Environment]::GetEnvironmentVariables("Machine")
    $userEnv.Keys | ForEach-Object { [System.Environment]::SetEnvironmentVariable($_, $userEnv[$_], "Process") }
    $machineEnv.Keys | ForEach-Object { [System.Environment]::SetEnvironmentVariable($_, $machineEnv[$_], "Process") }
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$machinePath;$userPath"
    Write-Host "Environment variables refreshed!" -ForegroundColor Green
}
if (Get-Alias ls -ErrorAction SilentlyContinue) { Remove-Item alias:ls -Force }
if (Get-Alias wget -ErrorAction SilentlyContinue) { Remove-Item alias:wget -Force }
if (Get-Alias curl -ErrorAction SilentlyContinue) { Remove-Item alias:curl -Force }
function ls { eza @args }
function l { eza -l @args }
function ll { eza -alF @args }
function la { eza -A @args }
function bottom { btm @args }
# endregion`},
		{"dev", "# region Guepardo Dev Shortcuts", `# region Guepardo Dev Shortcuts
function docker { podman @args }
function docker-compose { podman compose @args }
# endregion`},
		{"web", "# region Guepardo Web Shortcuts", `# region Guepardo Web Shortcuts
function a { php artisan @args }
# endregion`},
	}
	for _, profilePath := range profilePaths {
		content, err := os.ReadFile(profilePath)
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		profileText, encodeProfileText := decodePowerShellProfile(content)
		updated := append([]byte(nil), content...)
		for _, block := range blocks {
			if !hasProfile(profiles, block.profile) || strings.Contains(profileText, block.marker) {
				continue
			}
			addition := "\r\n" + strings.ReplaceAll(block.text, "\n", "\r\n") + "\r\n"
			updated = append(updated, encodeProfileText(addition)...)
			profileText += addition
		}
		if len(updated) == len(content) {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(profilePath), 0700); err != nil {
			return err
		}
		if err := os.WriteFile(profilePath, updated, 0600); err != nil {
			return err
		}
	}
	return nil
}

func decodePowerShellProfile(data []byte) (string, func(string) []byte) {
	if len(data) >= 2 && data[0] == 0xFF && data[1] == 0xFE {
		units := make([]uint16, 0, (len(data)-2)/2)
		for index := 2; index+1 < len(data); index += 2 {
			units = append(units, binary.LittleEndian.Uint16(data[index:index+2]))
		}
		return string(utf16.Decode(units)), func(value string) []byte {
			units := utf16.Encode([]rune(value))
			encoded := make([]byte, len(units)*2)
			for index, unit := range units {
				binary.LittleEndian.PutUint16(encoded[index*2:], unit)
			}
			return encoded
		}
	}
	if len(data) >= 2 && data[0] == 0xFE && data[1] == 0xFF {
		units := make([]uint16, 0, (len(data)-2)/2)
		for index := 2; index+1 < len(data); index += 2 {
			units = append(units, binary.BigEndian.Uint16(data[index:index+2]))
		}
		return string(utf16.Decode(units)), func(value string) []byte {
			units := utf16.Encode([]rune(value))
			encoded := make([]byte, len(units)*2)
			for index, unit := range units {
				binary.BigEndian.PutUint16(encoded[index*2:], unit)
			}
			return encoded
		}
	}
	if len(data) >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
		return string(data[3:]), func(value string) []byte { return []byte(value) }
	}
	return string(data), func(value string) []byte { return []byte(value) }
}
