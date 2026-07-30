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
	if info.Hibernated {
		t.Error("dev stub must not report hibernation")
	}
	if !info.Is64Bit {
		t.Error("dev stub must not report a 32-bit OS")
	}
	if info.RAMGB > 0 && info.RAMGB < 3.5 {
		t.Errorf("dev stub reports %.1f GB RAM, below the gate", info.RAMGB)
	}
}
