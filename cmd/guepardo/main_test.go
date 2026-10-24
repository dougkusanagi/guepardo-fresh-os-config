package main

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
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
		{"full", []string{"cli", "dev", "web", "desktop", "games"}},
		{"wsl", []string{"cli", "dev", "web"}},
		{"todos", []string{"cli", "dev", "web", "desktop", "games", "network"}},
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
		{"all includes network", "7\r", "cli,dev,web,desktop,games,network"},
		{"empty selection cannot continue", "\r6\r", "network"},
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

func TestSudoSessionRefreshesWithoutPrompt(t *testing.T) {
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

func TestRunProfileReportsFailureAndKeepsDiagnostics(t *testing.T) {
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "scripts"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "scripts", "run-profile.sh"), []byte("#!/bin/bash\necho 'Verbose package output'\necho 'ERROR package download failed'\nexit 42\n"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, interactive := range []bool{false, true} {
		var output, log bytes.Buffer
		err := runProfile(context.Background(), root, "ubuntu", "dev", "", false, 1, "", [5]string{}, interactive, &output, &log)
		if err == nil || !strings.Contains(output.String(), "package download failed") || !strings.Contains(log.String(), "package download failed") {
			t.Fatalf("interactive=%v: error=%v output=%q log=%q", interactive, err, output.String(), log.String())
		}
		if !strings.Contains(log.String(), "Verbose package output") || (interactive && strings.Contains(output.String(), "Verbose package output")) {
			t.Fatalf("interactive=%v: package output should stay in the log: output=%q log=%q", interactive, output.String(), log.String())
		}
	}
}

func TestRunProfileCancellationStopsChildInstallers(t *testing.T) {
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
		done <- runProfile(ctx, root, "ubuntu", "cli", "", false, 1, "", [5]string{}, false, io.Discard, io.Discard)
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

func TestPickerEnvironmentIsFixed(t *testing.T) {
	for _, wsl := range []bool{false, true} {
		p := newProfilePickerForEnvironment(wsl)
		var out bytes.Buffer
		p.render(&out, false)
		if !wsl && strings.Contains(out.String(), "WSL") {
			t.Fatal("Linux still shows WSL")
		}
		if strings.Contains(out.String(), "trocar") || strings.Contains(out.String(), "Tab/W") {
			t.Fatal("environment switch still shown")
		}
		got, err := selectProfilesWithPicker(strings.NewReader("w\t\x1b[C1\r"), io.Discard, false, p)
		want := "cli"
		if wsl {
			want = "dev,web"
		}
		if err != nil || got != want || p.wsl != wsl {
			t.Fatalf("environment changed: got=%s err=%v", got, err)
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
	p := newProfilePickerForEnvironment(true)
	p.width, p.height = 60, 24
	var output bytes.Buffer
	p.render(&output, false)
	text := output.String()
	for _, want := range []string{"guepardo", "WSL", "3 módulos selecionados"} {
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
		p.toggle(5)
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
	p := newProfilePickerForEnvironment(true)
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
	p.toggle(6)
	p = newProfilePickerForEnvironment(false)
	p.toggle(6)
	if !p.allSelected() {
		t.Fatal("Linux Todos no longer selects all profiles")
	}
}

func TestConfirmInstallation(t *testing.T) {
	for _, tc := range []struct {
		name, input string
		want        bool
	}{
		{"enter starts", "\n", true},
		{"whitespace starts", "  \n", true},
		{"yes", "s\n", true},
		{"uppercase yes", " S \n", true},
		{"no cancels", "n\n", false},
		{"invalid cancels", "maybe\n", false},
		{"EOF cancels", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var output bytes.Buffer
			got, err := confirmInstallation(strings.NewReader(tc.input), &output)
			if err != nil || got != tc.want {
				t.Fatalf("confirmation = %v, %v; want %v", got, err, tc.want)
			}
			if !strings.Contains(output.String(), "[S/n]") {
				t.Fatal(output.String())
			}
		})
	}
}

func TestFontsProfileRemoved(t *testing.T) {
	if _, err := parseProfiles("fonts"); err == nil {
		t.Fatal("removed fonts profile is accepted")
	}
	p := newProfilePickerForEnvironment(false)
	var output bytes.Buffer
	p.render(&output, false)
	if strings.Contains(output.String(), "Fontes") || !strings.Contains(output.String(), "1–7") {
		t.Fatal(output.String())
	}
	p.toggle(len(p.availableProfiles()))
	if p.profiles() != "cli,dev,web,desktop,games,network" {
		t.Fatal(p.profiles())
	}
}
