package main

import (
	"os"
	"path/filepath"
	"testing"
)

// listWindowsProfiles decides who gets a Linux account, so both directions
// matter: missing a real person means their files are silently left behind
// (the bridge skips profiles with no matching account), while inventing one
// for a system or leftover directory puts a stranger on the login screen.
// It also decides the directory→account map the first-boot bridge uses, so
// the WindowsDir half must stay the RAW directory name.
func TestListWindowsProfiles(t *testing.T) {
	users := filepath.Join(t.TempDir(), "Users")

	// A real profile is a directory containing NTUSER.DAT.
	real := func(name string) {
		d := filepath.Join(users, name)
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(d, "NTUSER.DAT"), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	bare := func(name string) {
		if err := os.MkdirAll(filepath.Join(users, name), 0o755); err != nil {
			t.Fatal(err)
		}
	}

	real("James Reilly")     // the installer-runner's own profile directory
	real("Alice Smith")      // a real second user, needs sanitising
	real("bob")              // a real third user
	real("Public")           // system
	real("defaultuser0")     // OOBE leftover — Windows often fails to delete it
	bare("Default")          // system, and no NTUSER.DAT
	bare("leftover-profile") // a directory that was never a logged-in user
	if err := os.WriteFile(filepath.Join(users, "desktop.ini"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	// The primary chose the username "james" — nothing like the directory
	// name. Exclusion must work on the DIRECTORY, or the person who ran the
	// installer gets a locked doppelganger account (and the bridge's #73
	// single-user fallback breaks).
	got := listProfilesIn(users, "james", "James Reilly")

	want := []profileMapping{
		{WindowsDir: "Alice Smith", LinuxUser: "alice-smith"},
		{WindowsDir: "bob", LinuxUser: "bob"},
	}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v (sorted, deterministic)", got, want)
		}
	}
}

// A profile whose directory happens to match the primary username must not be
// duplicated either — fisherman already created that account.
func TestListWindowsProfilesPrimaryNameCollision(t *testing.T) {
	users := filepath.Join(t.TempDir(), "Users")
	d := filepath.Join(users, "jreilly")
	if err := os.MkdirAll(d, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(d, "NTUSER.DAT"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := listProfilesIn(users, "jreilly", ""); len(got) != 0 {
		t.Errorf("got %v, want none — primary user must be excluded", got)
	}
}

func TestListWindowsProfilesNoUsersDir(t *testing.T) {
	if got := listProfilesIn(filepath.Join(t.TempDir(), "Users"), "jreilly", "jreilly"); got != nil {
		t.Errorf("got %v, want nil when there is no Users directory", got)
	}
}

// Non-Latin profiles (CJK, Cyrillic) and collisions after truncation must
// receive winuserN fallback accounts instead of being silently dropped (#197, #224).
func TestListWindowsProfilesNonLatinAndCollisionFallbacks(t *testing.T) {
	users := filepath.Join(t.TempDir(), "Users")
	createProfile := func(name string) {
		d := filepath.Join(users, name)
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(d, "NTUSER.DAT"), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	createProfile("田中")                               // CJK: sanitizes to "" -> winuser1
	createProfile("Иван")                             // Cyrillic: sanitizes to "" -> winuser2
	createProfile("very-long-profile-name-that-truncates-1111") // truncates to 32 chars
	createProfile("very-long-profile-name-that-truncates-2222") // collides on same 32 chars -> winuser3

	got := listProfilesIn(users, "primary", "PrimaryUser")

	want := []profileMapping{
		{WindowsDir: "very-long-profile-name-that-truncates-1111", LinuxUser: "very-long-profile-name-that-trun"},
		{WindowsDir: "very-long-profile-name-that-truncates-2222", LinuxUser: "winuser1"},
		{WindowsDir: "Иван", LinuxUser: "winuser2"},
		{WindowsDir: "田中", LinuxUser: "winuser3"},
	}

	if len(got) != len(want) {
		t.Fatalf("got %d profiles (%v), want %d (%v)", len(got), got, len(want), want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("[%d] got %v, want %v", i, got[i], want[i])
		}
	}
}

// Localized built-in system accounts (Administrator, Guest, DefaultAccount in
// French, German, Spanish, Russian, Chinese, Japanese, etc.) must not become
// login-screen accounts (#197, #224).
func TestListWindowsProfilesLocalizedBuiltinsExcluded(t *testing.T) {
	users := filepath.Join(t.TempDir(), "Users")
	createProfile := func(name string) {
		d := filepath.Join(users, name)
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(d, "NTUSER.DAT"), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	// Built-in accounts across locales
	createProfile("Administrateur")           // French Admin
	createProfile("Invité")                   // French Guest
	createProfile("Gast")                     // German Guest
	createProfile("Administrador")            // Spanish Admin
	createProfile("Invitado")                 // Spanish Guest
	createProfile("Администратор")            // Russian Admin
	createProfile("Гость")                    // Russian Guest
	createProfile("管理员")                    // Chinese Admin
	createProfile("管理者")                    // Japanese Admin
	createProfile("ゲスト")                    // Japanese Guest
	createProfile("Guest")                    // English Guest
	createProfile("All Users")                // English Builtin

	// A real user
	createProfile("realuser")

	got := listProfilesIn(users, "admin", "admin")
	want := []profileMapping{
		{WindowsDir: "realuser", LinuxUser: "realuser"},
	}

	if len(got) != len(want) {
		t.Fatalf("got %v, want %v (all localized built-ins must be excluded)", got, want)
	}
	if got[0] != want[0] {
		t.Fatalf("got %v, want %v", got[0], want[0])
	}
}
