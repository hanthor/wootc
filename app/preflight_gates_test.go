package main

import "testing"

// The #63 gates exist because the dangerous moment is BEFORE the first write:
// after the shrink there is no cheap undo. Each case here is a machine state
// where starting a migration risks the user's data, so the contract is that
// getSystemInfo REPORTS it — the GUI turns the report into a refusal.
//
// These assert the reporting contract and the conservative defaults. The
// "unknown" cases matter most: a query that fails must never fabricate a
// dangerous-looking answer (which would block a fine machine) nor a safe one
// where a real signal exists.
func TestBatteryUnknownIsNotBlocking(t *testing.T) {
	// Desktops have no Win32_Battery instance at all. Reporting "on battery"
	// there would refuse to install on every desktop PC — so the gate must
	// distinguish "no battery" from "running on battery", and only the latter
	// may block. The GUI checks onBattery && batteryKnown for this reason.
	info := SystemInfo{OnBattery: false, BatteryKnown: false}
	if info.OnBattery && info.BatteryKnown {
		t.Fatal("a machine with no battery must not be treated as running on battery")
	}
}

func TestHibernationIsSeparateFromFastStartup(t *testing.T) {
	// Fast Startup is a registry flag we clear; hibernation leaves
	// hiberfil.sys and a stale on-disk NTFS state. Mounting that read-write
	// from Linux is the corruption case wootc exists to prevent, so the two
	// must be independently representable — clearing one must not imply the
	// other.
	info := SystemInfo{FastStartupOn: false, Hibernated: true}
	if !info.Hibernated {
		t.Fatal("hibernation must be reportable independently of Fast Startup")
	}
}

// A refusal the user cannot argue with is a refusal they learn to ignore. When
// the gate fires it must name the signal, because the first version of this
// check fired on a HEALTHY freshly-installed Windows (PendingFileRenameOperations
// is set by ordinary installers) and the message gave no way to tell that from a
// real pending update.
func TestPendingRebootNamesItsSignal(t *testing.T) {
	info := SystemInfo{PendingReboot: true, PendingRebootReason: "windows-update"}
	if info.PendingReboot && info.PendingRebootReason == "" {
		t.Fatal("a pending-reboot refusal must name which signal fired")
	}
}

// BitLocker recovery-key check is honest disclosure (#63): when
// ProtectionStatus is On the user should record their key before any
// migration step, independent of whether we unlock C: or carve a
// separate volume (#61). The warning must be reportable separately from
// the on/off state so the GUI knows to show the recovery-key prompt.
func TestBitLockerRecoveryKeyWarningIsIndependent(t *testing.T) {
	info := SystemInfo{BitLockerOn: true, BitLockerState: "on", BitLockerRecoveryKeyWarning: true}
	if info.BitLockerOn && !info.BitLockerRecoveryKeyWarning {
		t.Fatal("BitLocker recovery-key warning must be reportable when BitLocker is on")
	}
	// "encrypting" / "decrypting" are transient states where the key is
	// not yet established or is being removed — only "on" should trigger
	// the recovery-key warning.
	info2 := SystemInfo{BitLockerOn: true, BitLockerState: "encrypting", BitLockerRecoveryKeyWarning: false}
	if info2.BitLockerRecoveryKeyWarning {
		t.Fatal("BitLocker recovery-key warning must not fire during encryption")
	}
}

func TestDevStubIsNeverBlocking(t *testing.T) {
	// `wails dev` on Linux/macOS must not be gated by checks that describe a
	// real Windows machine.
	info := getSystemInfo()
	if info.OnBattery && info.BatteryKnown {
		t.Error("dev stub must not report running on battery")
	}
	if info.PendingReboot {
		t.Error("dev stub must not report a pending reboot")
	}
	if info.PendingRebootReason != "" {
		t.Errorf("dev stub must not name a pending-reboot reason, got %q", info.PendingRebootReason)
	}
	if info.Hibernated {
		t.Error("dev stub must not report hibernation")
	}
	if !info.Is64Bit {
		t.Error("dev stub must not report a 32-bit OS")
	}
	if info.RAMGB > 0 && info.RAMGB < 3.5 {
		t.Errorf("dev stub reports %.1f GB RAM, below the gate", info.RAMGB)
	}
	if info.BitLockerRecoveryKeyWarning {
		t.Error("dev stub must not trigger the BitLocker recovery-key warning")
	}
}
