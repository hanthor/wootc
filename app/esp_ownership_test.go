package main

import (
	"os"
	"path/filepath"
	"testing"
)

// #52: installing wootc must never make an existing Linux unbootable. These
// tests use real ESP-shaped trees, because the bug being prevented is
// "a file existed and we wrote over it" — which only a filesystem can show.

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// A real Fedora owns EFI\fedora\shimx64.efi. Its grub.cfg may live elsewhere,
// so the old marker-on-grub.cfg check would pass and we would clobber a signed
// bootloader belonging to another OS.
func TestForeignShimBlocksInstall(t *testing.T) {
	esp := t.TempDir()
	writeFile(t, filepath.Join(esp, "EFI", "fedora", "shimx64.efi"), "real fedora shim")

	err := guardESPDestinations(esp, []string{filepath.Join("EFI", "fedora", "shimx64.efi")})
	if err == nil {
		t.Fatal("expected a refusal: EFI/fedora/shimx64.efi belongs to another OS")
	}
	// The message has to name the file — "installation failed" tells a user
	// nothing about what is on their disk.
	if !contains(err.Error(), "shimx64.efi") {
		t.Errorf("refusal must name the offending file, got: %v", err)
	}
}

// A wootc reinstall must not be blocked by its own previous files.
func TestOwnFilesAllowReinstall(t *testing.T) {
	esp := t.TempDir()
	rels := []string{
		filepath.Join("EFI", "fedora", "shimx64.efi"),
		filepath.Join("EFI", "wootc", "deployer-vmlinuz"),
	}
	for _, r := range rels {
		writeFile(t, filepath.Join(esp, r), "wootc-written")
	}
	if err := recordESPOwnership(esp, rels); err != nil {
		t.Fatal(err)
	}
	if err := guardESPDestinations(esp, rels); err != nil {
		t.Fatalf("a reinstall must proceed over wootc's own files, got: %v", err)
	}
}

// Claiming our files must not claim a neighbour's. This is the "preserve
// unrelated vendor directories byte-for-byte" criterion.
func TestOwnershipDoesNotClaimNeighbours(t *testing.T) {
	esp := t.TempDir()
	ours := filepath.Join("EFI", "fedora", "shimx64.efi")
	theirs := filepath.Join("EFI", "ubuntu", "shimx64.efi")
	writeFile(t, filepath.Join(esp, ours), "wootc")
	writeFile(t, filepath.Join(esp, theirs), "ubuntu's bootloader")

	if err := recordESPOwnership(esp, []string{ours}); err != nil {
		t.Fatal(err)
	}
	if err := guardESPDestinations(esp, []string{theirs}); err == nil {
		t.Fatal("claiming our own files must not grant ownership of another vendor's")
	}
	// And their file is untouched.
	got, err := os.ReadFile(filepath.Join(esp, theirs))
	if err != nil || string(got) != "ubuntu's bootloader" {
		t.Errorf("neighbour's bootloader was modified: %q (%v)", got, err)
	}
}

// FAT32 is case-insensitive and tools disagree about separators; ownership must
// survive both or a reinstall wrongly reads as a foreign OS.
func TestOwnershipIgnoresCaseAndSeparators(t *testing.T) {
	esp := t.TempDir()
	writeFile(t, filepath.Join(esp, "EFI", "wootc", "deployer-vmlinuz"), "x")
	if err := recordESPOwnership(esp, []string{`EFI\wootc\deployer-vmlinuz`}); err != nil {
		t.Fatal(err)
	}
	if err := guardESPDestinations(esp, []string{"efi/WOOTC/deployer-vmlinuz"}); err != nil {
		t.Fatalf("ownership must be case- and separator-insensitive, got: %v", err)
	}
}

// An absent destination is the normal first install.
func TestAbsentDestinationIsFine(t *testing.T) {
	esp := t.TempDir()
	if err := guardESPDestinations(esp, []string{filepath.Join("EFI", "fedora", "shimx64.efi")}); err != nil {
		t.Fatalf("a clean ESP must install without complaint, got: %v", err)
	}
}

func contains(haystack, needle string) bool {
	return len(haystack) >= len(needle) && (func() bool {
		for i := 0; i+len(needle) <= len(haystack); i++ {
			if haystack[i:i+len(needle)] == needle {
				return true
			}
		}
		return false
	})()
}
