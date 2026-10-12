package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
	"time"
	"unicode/utf16"
	"unicode/utf8"
)

func TestParseProfilesSeparatesScopes(t *testing.T) {
	tests := []struct {
		input string
		want  []string
	}{
		{"server", []string{"cli"}},
		{"games", []string{"games"}},
		{"desktop,games", []string{"desktop", "games"}},
		{"web,cli,cli", []string{"cli", "web"}},
		{"full", []string{"cli", "dev", "web", "desktop", "games", "fonts"}},
		{"wsl", []string{"cli", "dev", "web"}},
		{"todos", []string{"cli", "dev", "web", "desktop", "games", "fonts", "network"}},
	}
	for _, tc := range tests {
		t.Run(tc.input, func(t *testing.T) {
			got, err := parseProfiles(tc.input)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("profiles = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestProfilePickerKeyboardSelection(t *testing.T) {
	tests := []struct {
		name, keys, want string
	}{
		{"numbers toggle several", "1234\r", "cli,dev,web,desktop"},
		{"space toggles focused row", "\x1b[B \r", "dev"},
		{"all includes network", "8\r", "cli,dev,web,desktop,games,fonts,network"},
		{"empty selection cannot continue", "\r7\r", "network"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var output bytes.Buffer
			got, err := selectProfiles(strings.NewReader(tc.keys), &output, false)
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.want {
				t.Fatalf("selection = %q, want %q", got, tc.want)
			}
			if !strings.Contains(output.String(), "●") || !strings.Contains(output.String(), "Todos") {
				t.Fatalf("picker did not render checkboxes and Todos: %q", output.String())
			}
		})
	}
}

func TestProfilePickerCancel(t *testing.T) {
	if _, err := selectProfiles(strings.NewReader("q"), io.Discard, false); err == nil {
		t.Fatal("cancel was ignored")
	}
}

func TestPromptNetworkSettings(t *testing.T) {
	opts := options{}
	if err := promptNetworkSettings(&opts, strings.NewReader("enp1s0\n192.168.1.77/24\n192.168.1.1\n\n"), io.Discard); err != nil {
		t.Fatal(err)
	}
	if opts.networkInterface != "enp1s0" || opts.networkAddress != "192.168.1.77/24" || opts.networkGateway != "192.168.1.1" || opts.networkDNS != "1.1.1.1" {
		t.Fatalf("unexpected network settings: %+v", opts)
	}
}

func TestSudoSessionRefreshesWithoutPrompt(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("sudo session uses a POSIX test executable")
	}
	dir := t.TempDir()
	calls := filepath.Join(dir, "calls")
	stub := filepath.Join(dir, "sudo")
	if err := os.WriteFile(stub, []byte("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$GUEPARDO_TEST_CALLS\"\n"), 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GUEPARDO_TEST_CALLS", calls)
	t.Setenv("SUDO_ASKPASS", filepath.Join(dir, "askpass"))
	previous := sudoRefreshInterval
	sudoRefreshInterval = 10 * time.Millisecond
	defer func() { sudoRefreshInterval = previous }()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stop, failures, err := sudoSession(ctx, cancel, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(50 * time.Millisecond)
	stop()
	select {
	case err := <-failures:
		t.Fatalf("unexpected sudo failure: %v", err)
	default:
	}
	data, err := os.ReadFile(calls)
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	if !strings.Contains(got, "-A -v") || !strings.Contains(got, "-n -v") {
		t.Fatalf("expected initial authentication and noninteractive refresh, got %q", got)
	}
}

func TestParseProfilesRejectsUnknown(t *testing.T) {
	for _, input := range []string{"", "cli,unknown", "serverr"} {
		if _, err := parseProfiles(input); err == nil {
			t.Errorf("parseProfiles(%q) accepted an invalid selection", input)
		}
	}
}

func TestParseWindowsProfilesAndPresets(t *testing.T) {
	for _, tc := range []struct {
		input string
		want  []string
	}{
		{"full", []string{"cli", "dev", "web", "desktop", "games", "jellyfin", "wsl2"}},
		{"basic", []string{"cli", "dev", "web"}},
		{"wsl", []string{"cli", "dev", "web", "wsl2"}},
		{"wsl2", []string{"wsl2"}},
		{"desktop,games", []string{"desktop", "games"}},
		{"jellyfin,cli,cli", []string{"cli", "jellyfin"}},
	} {
		got, err := parseWindowsProfiles(tc.input)
		if err != nil || !reflect.DeepEqual(got, tc.want) {
			t.Fatalf("parseWindowsProfiles(%q) = %v, %v; want %v", tc.input, got, err, tc.want)
		}
	}
	for _, invalid := range []string{"", "network", "fonts", "dev,unknown"} {
		if _, err := parseWindowsProfiles(invalid); err == nil {
			t.Errorf("parseWindowsProfiles(%q) accepted an invalid profile", invalid)
		}
	}
}

func TestWindowsPackageCatalogUnifiesOneDriveApps(t *testing.T) {
	profiles, err := parseWindowsProfiles("full")
	if err != nil {
		t.Fatal(err)
	}
	packages := windowsPackages(profiles)
	ids := make(map[string]bool, len(packages))
	for _, app := range packages {
		if ids[app.id] {
			t.Fatalf("duplicate package %q in full plan", app.id)
		}
		ids[app.id] = true
	}
	for _, id := range []string{
		"GitHub.cli", "Git.Git", "sharkdp.bat", "Clement.bottom", "sharkdp.fd",
		"junegunn.fzf", "BurntSushi.ripgrep.MSVC", "chmln.sd", "dbrgn.tealdeer",
		"jqlang.jq", "eza-community.eza", "bootandy.dust", "JesseDuffield.lazygit",
		"sxyazi.yazi",
		"7zip.7zip", "Microsoft.PowerToys", "Google.Chrome", "Brave.Brave",
		"RARLab.WinRAR", "Skillbrains.Lightshot", "RevoUninstaller.RevoUninstaller",
		"ZedIndustries.Zed", "GitHub.GitHubDesktop", "Termius.Termius", "T3Tools.T3Code",
		"GitHub.cli", "Git.Git", "Oven-sh.Bun", "astral-sh.uv", "CoreyButler.NVMforWindows",
		"Anthropic.Claude", "Telegram.TelegramDesktop", "Zen-Team.Zen-Browser",
		"Gyan.FFmpeg", "VideoLAN.VLC", "OBSProject.OBSStudio", "Canva.Affinity",
		"CodecGuide.K-LiteCodecPack.Mega", "ElementLabs.LMStudio", "GodotEngine.GodotEngine",
		"Comfy.ComfyUI-Desktop", "ElementLabs.Bionic", "qBittorrent.qBittorrent",
		"Stremio.Stremio", "Jellyfin.Server", "Valve.Steam", "EpicGames.EpicGamesLauncher", "Warp.Warp",
		"GnuPG.Gpg4win", "wget", "unzip", "OpenAI.Codex", "SST.opencode",
	} {
		if !ids[id] {
			t.Errorf("full Windows plan is missing OneDrive package %s", id)
		}
	}
}

func TestWindowsCLIUsesScoopOnlyForMissingPortableCommands(t *testing.T) {
	profiles, err := parseWindowsProfiles("cli")
	if err != nil {
		t.Fatal(err)
	}
	packages := windowsPackages(profiles)
	if !windowsPackagesNeedManager(packages, windowsPackageManagerWinget) || !windowsPackagesNeedManager(packages, windowsPackageManagerScoop) {
		t.Fatal("CLI profile must use Winget and Scoop")
	}
	for _, app := range packages {
		want := windowsPackageManagerWinget
		if app.id == "wget" || app.id == "unzip" {
			want = windowsPackageManagerScoop
		}
		if got := windowsPackageManagerFor(app); got != want {
			t.Errorf("manager for %s = %s, want %s", app.id, got, want)
		}
	}
	for _, packageID := range []string{"wget", "unzip"} {
		script := windowsScoopPowerShellScript(packageID)
		for _, want := range []string{"https://get.scoop.sh", "RemoteSigned -Scope CurrentUser", "apps\\scoop\\current\\bin\\scoop.ps1", "& $scoopScript install '" + packageID + "'"} {
			if !strings.Contains(script, want) {
				t.Errorf("Scoop setup script for %s is missing %q", packageID, want)
			}
		}
	}
	if got := windowsScoopPowerShellArgs("wget"); !reflect.DeepEqual(got[:5], []string{"-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand"}) {
		t.Fatalf("Scoop PowerShell invocation prefix = %v", got[:5])
	}
}

func TestWindowsNodeLTSPowerShellScriptUsesNVMAndPreservesSupportedNode(t *testing.T) {
	script := windowsNodeLTSPowerShellScript()
	for _, want := range []string{"GetEnvironmentVariable", "nvm.exe", "install lts", "use lts", "^v(22|24)\\.", "npm.cmd"} {
		if !strings.Contains(script, want) {
			t.Errorf("Node LTS setup script is missing %q", want)
		}
	}
}

func TestWindowsGeneratedPowerShellScriptsParse(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("PowerShell parser validation runs on Windows")
	}
	powershell, err := exec.LookPath("powershell.exe")
	if err != nil {
		t.Skip("Windows PowerShell is unavailable")
	}
	root := t.TempDir()
	profiles := []string{"cli", "dev", "web"}
	t.Setenv("USERPROFILE", root)
	if err := configureWindowsPowerShellProfile(profiles); err != nil {
		t.Fatal(err)
	}
	scripts := map[string]string{
		"scoop-bootstrap.ps1": windowsScoopPowerShellScript("unzip"),
		"node-lts.ps1":        windowsNodeLTSPowerShellScript(),
		"wsl-admin.ps1":       windowsWSLAdminPowerShellScript(),
		"wsl-wrapper.ps1":     windowsWSLPowerShellScript(),
		"WindowsPowerShell\\Microsoft.PowerShell_profile.ps1": string(mustReadFile(t, filepath.Join(root, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"))),
		"PowerShell\\Microsoft.PowerShell_profile.ps1":        string(mustReadFile(t, filepath.Join(root, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1"))),
	}
	paths := make([]string, 0, len(scripts))
	for name, script := range scripts {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(script), 0600); err != nil {
			t.Fatal(err)
		}
		paths = append(paths, path)
	}
	checker := filepath.Join(root, "parse-powershell.ps1")
	command := `$ErrorActionPreference = 'Stop'; foreach ($path in $args) { $tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { Write-Error ($errors | Out-String); exit 1 } }`
	if err := os.WriteFile(checker, []byte(command), 0600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(powershell, append([]string{"-NoLogo", "-NoProfile", "-File", checker}, paths...)...)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("generated PowerShell script did not parse: %v\n%s", err, output)
	}
}

func TestWindowsWSLProfileAndPlan(t *testing.T) {
	profiles, err := parseWindowsProfiles("wsl2")
	if err != nil || !reflect.DeepEqual(profiles, []string{"wsl2"}) {
		t.Fatalf("parseWindowsProfiles(wsl2) = %v, %v", profiles, err)
	}
	if packages := windowsPackages(profiles); len(packages) != 0 {
		t.Fatalf("WSL profile unexpectedly contains package manager apps: %v", packages)
	}
	var plan bytes.Buffer
	printWindowsPlan(&plan, profiles, nil)
	for _, want := range []string{"WSL 2", "Ubuntu", "Virtual Machine Platform", "Hyper-V", "Nenhum aplicativo ou configuração foi alterado"} {
		if !strings.Contains(plan.String(), want) {
			t.Errorf("WSL plan is missing %q: %s", want, plan.String())
		}
	}
	for _, tc := range []struct {
		code int
		want string
	}{{0, "configured"}, {3010, "reboot-required"}, {1, "failed"}} {
		if got := classifyWindowsWSLExitCode(tc.code); got != tc.want {
			t.Errorf("classifyWindowsWSLExitCode(%d) = %q, want %q", tc.code, got, tc.want)
		}
	}
	adminScript := windowsWSLAdminPowerShellScript()
	for _, want := range []string{
		"--install --distribution Ubuntu --no-launch",
		"--update",
		"--set-default-version 2",
		"--set-version Ubuntu 2",
		"--set-default Ubuntu",
		"Microsoft-Windows-Subsystem-Linux",
		"VirtualMachinePlatform",
		"Enable-WindowsOptionalFeature",
		"RestartNeeded",
	} {
		if !strings.Contains(adminScript, want) {
			t.Errorf("WSL setup script is missing %q", want)
		}
	}
	if strings.Contains(adminScript, "Microsoft-Hyper-V-All") {
		t.Fatal("WSL setup must not enable the full Hyper-V feature")
	}
	if !strings.Contains(windowsWSLPowerShellScript(), "-Verb RunAs") {
		t.Fatal("WSL setup must request UAC elevation")
	}
}

func mustReadFile(t *testing.T, path string) []byte {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return content
}

func TestWindowsWingetInvocationAndExitCodes(t *testing.T) {
	wantArgs := []string{"install", "-e", "--id", "RevoUninstaller.RevoUninstaller", "--source", "winget", "--silent", "--disable-interactivity", "--no-upgrade", "--accept-package-agreements", "--accept-source-agreements"}
	if got := windowsWingetArgs("RevoUninstaller.RevoUninstaller"); !reflect.DeepEqual(got, wantArgs) {
		t.Fatalf("winget args = %v, want %v", got, wantArgs)
	}
	for _, tc := range []struct {
		code int
		want string
	}{
		{0, "installed"}, {-1978335189, "already-installed"}, {-1978335135, "already-installed"},
		{-1978334963, "already-installed"}, {3010, "reboot-required"}, {-1978334967, "reboot-required"}, {1, "failed"},
	} {
		if got := classifyWingetExitCode(tc.code); got != tc.want {
			t.Errorf("classifyWingetExitCode(%d) = %s, want %s", tc.code, got, tc.want)
		}
	}
}

func TestWindowsPickerPresentationAndSelection(t *testing.T) {
	p := newProfilePicker()
	p.windows = true
	p.width, p.height = 60, 24
	var output bytes.Buffer
	p.render(&output, false)
	for _, want := range []string{"Windows", "Winget", "Jellyfin completo", "WSL 2 + Ubuntu", "0 módulos"} {
		if !strings.Contains(output.String(), want) {
			t.Errorf("Windows picker is missing %q", want)
		}
	}
	if strings.Contains(output.String(), "Tab / W trocar") {
		t.Fatal("Windows picker should not offer Linux/WSL switching")
	}
	selected, err := selectProfilesWithPicker(strings.NewReader("6\r"), io.Discard, false, p)
	if err != nil || selected != "jellyfin" {
		t.Fatalf("Windows picker selected %q, %v; want jellyfin", selected, err)
	}
	p.selected = make(map[string]bool)
	selected, err = selectProfilesWithPicker(strings.NewReader("7\r"), io.Discard, false, p)
	if err != nil || selected != "wsl2" {
		t.Fatalf("Windows picker selected %q, %v; want wsl2", selected, err)
	}
}

func TestWindowsPowerShellProfileUpdatePreservesEncodingAndIsIdempotent(t *testing.T) {
	home := t.TempDir()
	t.Setenv("USERPROFILE", home)
	path := filepath.Join(home, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	existing := "# existing profile\r\n"
	units := utf16.Encode([]rune(existing))
	data := []byte{0xFF, 0xFE}
	for _, unit := range units {
		chunk := make([]byte, 2)
		binary.LittleEndian.PutUint16(chunk, unit)
		data = append(data, chunk...)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := configureWindowsPowerShellProfile([]string{"cli", "dev", "web"}); err != nil {
		t.Fatal(err)
	}
	first, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) < 2 || first[0] != 0xFF || first[1] != 0xFE {
		t.Fatal("UTF-16LE profile BOM was not preserved")
	}
	decoded, _ := decodePowerShellProfile(first)
	if !strings.HasPrefix(decoded, existing) {
		t.Fatalf("existing profile text changed: %q", decoded)
	}
	if err := configureWindowsPowerShellProfile([]string{"cli", "dev", "web"}); err != nil {
		t.Fatal(err)
	}
	second, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(first, second) {
		t.Fatal("running profile configuration twice appended duplicate shortcuts")
	}
	pwshPath := filepath.Join(home, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1")
	pwshFirst, err := os.ReadFile(pwshPath)
	if err != nil {
		t.Fatalf("PowerShell 7 profile was not created: %v", err)
	}
	if err := configureWindowsPowerShellProfile([]string{"cli", "dev", "web"}); err != nil {
		t.Fatal(err)
	}
	pwshSecond, err := os.ReadFile(pwshPath)
	if err != nil || !bytes.Equal(pwshFirst, pwshSecond) {
		t.Fatalf("PowerShell 7 profile update was not idempotent: err=%v", err)
	}
	for _, profileData := range [][]byte{second, pwshSecond} {
		decodedProfile, _ := decodePowerShellProfile(profileData)
		for _, want := range []string{"function l { eza -l @args }", "function ll { eza -alF @args }", "function la { eza -A @args }", "function bottom { btm @args }", "Remove-Item alias:wget", "Remove-Item alias:curl"} {
			if !strings.Contains(decodedProfile, want) {
				t.Errorf("PowerShell profile is missing %q", want)
			}
		}
	}
}

func TestEmbeddedWindowsAssetsMaterializeForStandaloneExecutable(t *testing.T) {
	root, cleanup, err := materializeEmbeddedWindowsAssets()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	for _, file := range []string{"modules/jellyfin.ps1", "jellyfin/polish.css"} {
		if info, err := os.Stat(filepath.Join(root, filepath.FromSlash(file))); err != nil || info.Size() == 0 {
			t.Fatalf("embedded resource %s was not materialized: info=%v err=%v", file, info, err)
		}
	}
}

func TestRunProfileReportsFailureAndKeepsDiagnostics(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("profile runner invokes Bash")
	}
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "scripts"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "scripts", "run-profile.sh"), []byte("#!/bin/bash\necho 'Verbose package output'\necho 'ERROR package download failed'\nexit 42\n"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, interactive := range []bool{false, true} {
		var output, log bytes.Buffer
		err := runProfile(context.Background(), root, "ubuntu", "dev", "", false, 1, "", [4]string{}, interactive, &output, &log)
		if err == nil || !strings.Contains(output.String(), "package download failed") || !strings.Contains(log.String(), "package download failed") {
			t.Fatalf("interactive=%v: error=%v output=%q log=%q", interactive, err, output.String(), log.String())
		}
		if !strings.Contains(log.String(), "Verbose package output") || (interactive && strings.Contains(output.String(), "Verbose package output")) {
			t.Fatalf("interactive=%v: package output should stay in the log: output=%q log=%q", interactive, output.String(), log.String())
		}
	}
}

func TestRunProfileCancellationStopsChildInstallers(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("process group cancellation is Linux-specific")
	}
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "scripts"), 0700); err != nil {
		t.Fatal(err)
	}
	script := `#!/bin/bash
trap 'wait; exit 143' TERM
bash -c 'trap "touch child-stopped; exit 0" TERM; touch child-started; while true; do sleep 1; done' &
wait
`
	if err := os.WriteFile(filepath.Join(root, "scripts", "run-profile.sh"), []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- runProfile(ctx, root, "ubuntu", "cli", "", false, 1, "", [4]string{}, false, io.Discard, io.Discard)
	}()
	deadline := time.Now().Add(5 * time.Second)
	for {
		if _, err := os.Stat(filepath.Join(root, "child-started")); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("child installer did not start")
		}
		time.Sleep(10 * time.Millisecond)
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled installation reported success")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("cancelled installation did not stop")
	}
	if _, err := os.Stat(filepath.Join(root, "child-stopped")); err != nil {
		t.Fatal("child installer did not receive termination")
	}
}

func TestPickerEnvironmentSwitch(t *testing.T) {
	for _, tc := range []struct{ keys, want string }{
		{"w\r", "cli,dev,web"},
		{"\t\r", "cli,dev,web"},
		{"\x1b[C\r", "cli,dev,web"},
		{"w2\r", "cli,web"},
		{"w2ww\r", "cli,web"},
		{"4ww\r", "desktop"},
		{"w8\r", "cli,dev,web"},
		{"w44\r", "cli,dev,web"},
		{"w4a\r", "cli,dev,web"},
		{"w\x1b[A \x1b[B \r", "cli"},
	} {
		got, err := selectProfiles(strings.NewReader(tc.keys), io.Discard, false)
		if err != nil || got != tc.want {
			t.Fatalf("keys=%q: got=%q err=%v, want=%q", tc.keys, got, err, tc.want)
		}
	}
}

func TestPickerWSLDetection(t *testing.T) {
	t.Setenv("WSL_DISTRO_NAME", "Ubuntu")
	if !isWSLEnvironment() {
		t.Fatal("WSL environment was not detected")
	}
}

func TestPickerPresentation(t *testing.T) {
	p := newProfilePicker()
	p.width, p.height = 60, 24
	p.switchEnvironment()
	var output bytes.Buffer
	p.render(&output, false)
	text := output.String()
	for _, want := range []string{"guepardo", "Linux", "WSL", "Tab / W trocar", "3 módulos selecionados"} {
		if !strings.Contains(text, want) {
			t.Fatalf("missing %q in %q", want, text)
		}
	}
	if strings.Contains(text, "\x1b[38;") || strings.Contains(text, "\x1b[1;") {
		t.Fatal("NO_COLOR rendering contains color codes")
	}
	p.active = 2
	output.Reset()
	p.render(&output, true)
	if !strings.Contains(output.String(), "PHP, Composer") || !strings.Contains(output.String(), "48;2;") {
		t.Fatal("focused description/highlight missing")
	}
}

func TestPickerFitsTerminal(t *testing.T) {
	for _, size := range [][2]int{{40, 20}, {60, 24}, {80, 32}} {
		p := newProfilePicker()
		p.width, p.height = size[0], size[1]
		p.toggle(6)
		p.message = "Marque ao menos um perfil para continuar."
		var out bytes.Buffer
		p.render(&out, false)
		lines := strings.Split(strings.TrimSuffix(strings.TrimPrefix(out.String(), "\x1b[H\x1b[2J"), "\n"), "\n")
		if len(lines) > p.height {
			t.Fatalf("height %d: %d lines", p.height, len(lines))
		}
		for _, line := range lines {
			if utf8.RuneCountInString(line) >= p.width {
				t.Fatalf("width %d: overflowing line %q", p.width, line)
			}
		}
	}
}

func TestWSLPickerHidesUnsupportedModules(t *testing.T) {
	p := newProfilePicker()
	p.switchEnvironment()
	p.active = 3
	var output bytes.Buffer
	p.render(&output, false)
	for _, hidden := range []string{"Desktop", "Jogos", "Fontes", "Rede IPv4", "rede IPv4", "1–8"} {
		if strings.Contains(output.String(), hidden) {
			t.Fatalf("WSL menu still shows %q", hidden)
		}
	}
	if !strings.Contains(output.String(), "1–4") {
		t.Fatal("WSL shortcuts were not updated")
	}
	// A stray selection must never leak from the Linux environment into WSL.
	p.selected["desktop"] = true
	if got := p.profiles(); got != "cli,dev,web" {
		t.Fatalf("unsupported profile leaked: %s", got)
	}
	p.toggle(7)
	p.switchEnvironment()
	p.toggle(7)
	if !p.allSelected() {
		t.Fatal("Linux Todos no longer selects all profiles")
	}
}
