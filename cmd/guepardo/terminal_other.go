//go:build !linux && !windows

package main

import (
	"context"
	"os"
	"os/exec"
	"os/signal"
)

func configureProcessCancellation(_ *exec.Cmd) {}

func isTerminal(_ *os.File) bool { return false }

func isElevated() bool { return false }

func newSignalContext() (context.Context, context.CancelFunc) {
	return signal.NotifyContext(context.Background(), os.Interrupt)
}
