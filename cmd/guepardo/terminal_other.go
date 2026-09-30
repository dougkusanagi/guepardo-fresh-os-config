//go:build !linux

package main

import (
	"os"
	"os/exec"
)

func configureProcessCancellation(_ *exec.Cmd) {}

func isTerminal(_ *os.File) bool { return false }
