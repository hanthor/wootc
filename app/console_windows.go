//go:build windows

package main

import (
	"os"
	"syscall"

	"golang.org/x/sys/windows"
)

// attachParentConsole attaches the process to the console of its parent process.
// When wootc is compiled with -ldflags "-H windowsgui", Windows does not allocate
// a console window on launch. For headless CLI subcommands (install, status, uninstall)
// invoked from an existing terminal (e.g. PowerShell, cmd.exe), attaching to the
// parent console enables stdout/stderr to print directly to that terminal.
func attachParentConsole() {
	modkernel32 := syscall.NewLazyDLL("kernel32.dll")
	procAttachConsole := modkernel32.NewProc("AttachConsole")

	// ATTACH_PARENT_PROCESS is (DWORD)-1
	const attachParentProcess = ^uintptr(0)
	r1, _, _ := procAttachConsole.Call(attachParentProcess)
	if r1 == 0 {
		return
	}

	hStdout, err := windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)
	if err == nil && hStdout != windows.InvalidHandle {
		os.Stdout = os.NewFile(uintptr(hStdout), "/dev/stdout")
	}
	hStderr, err := windows.GetStdHandle(windows.STD_ERROR_HANDLE)
	if err == nil && hStderr != windows.InvalidHandle {
		os.Stderr = os.NewFile(uintptr(hStderr), "/dev/stderr")
	}
	hStdin, err := windows.GetStdHandle(windows.STD_INPUT_HANDLE)
	if err == nil && hStdin != windows.InvalidHandle {
		os.Stdin = os.NewFile(uintptr(hStdin), "/dev/stdin")
	}
}
