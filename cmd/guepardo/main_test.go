package main

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
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
