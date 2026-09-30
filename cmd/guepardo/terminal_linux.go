//go:build linux

package main

import (
	"os"
	"os/exec"
	"syscall"
	"time"
	"unsafe"
)

func configureProcessCancellation(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if err := syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM); err == syscall.ESRCH {
			return os.ErrProcessDone
		} else {
			return err
		}
	}
	cmd.WaitDelay = 5 * time.Second
}

func isTerminal(f *os.File) bool {
	var state syscall.Termios
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&state)))
	return errno == 0
}
