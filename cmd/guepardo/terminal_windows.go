//go:build windows

package main

import (
	"context"
	"os"
	"os/exec"
	"os/signal"

	"golang.org/x/term"
)

func configureProcessCancellation(_ *exec.Cmd) {}

func isTerminal(file *os.File) bool { return term.IsTerminal(int(file.Fd())) }

// Windows installers request elevation through Winget/UAC when needed.
func isElevated() bool { return false }

func newSignalContext() (context.Context, context.CancelFunc) {
	return signal.NotifyContext(context.Background(), os.Interrupt)
}
