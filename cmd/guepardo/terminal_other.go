//go:build !linux

package main

import "os"

func isTerminal(_ *os.File) bool { return false }
