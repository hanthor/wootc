package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ESP ownership manifest (#52).
//
// wootc writes into EFI\fedora — a directory a real Fedora or RHEL install
// also owns. Checking grub.cfg for our marker was not enough: we overwrite
// shimx64.efi and grubx64.efi too, and another distro owns those binaries even
// when its grub.cfg lives somewhere the marker check never looks. Overwriting
// them makes that OS unbootable, which is the opposite of this project's
// reversibility promise.
//
// So: record every file wootc writes to the ESP, and before writing, refuse if
// a destination exists that we did not write. A reinstall recognises its own
// files and proceeds; anything foreign stops the install BEFORE the first byte
// is changed, while the machine is still exactly as the user left it.
//
// The manifest is a plain text file — one relative path per line — deliberately
// readable by a human staring at a broken ESP with a rescue disk.
const espOwnershipManifest = `EFI\wootc\wootc-owned.txt`

func espManifestPath(espPath string) string {
	return filepath.Join(espPath, "EFI", "wootc", "wootc-owned.txt")
}

// readESPOwnership returns the set of ESP-relative paths wootc has written.
// A missing manifest is not an error: it means wootc has never installed here.
func readESPOwnership(espPath string) (map[string]bool, error) {
	owned := map[string]bool{}
	f, err := os.Open(espManifestPath(espPath))
	if err != nil {
		if os.IsNotExist(err) {
			return owned, nil
		}
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		owned[normalizeESPPath(line)] = true
	}
	return owned, sc.Err()
}

// normalizeESPPath makes comparisons independent of separator and case. ESPs
// are FAT32: case-insensitive, and written by tools that disagree about slashes.
func normalizeESPPath(p string) string {
	p = strings.ReplaceAll(p, `\`, "/")
	return strings.ToLower(strings.Trim(p, "/"))
}

// guardESPDestinations refuses to continue if any destination already exists
// and was not written by wootc. Called BEFORE the first write.
func guardESPDestinations(espPath string, relPaths []string) error {
	owned, err := readESPOwnership(espPath)
	if err != nil {
		// An unreadable manifest means we cannot prove ownership. Refusing is
		// the safe direction: the cost of a false refusal is an error message,
		// the cost of a false proceed is someone's bootloader.
		return fmt.Errorf("cannot read the record of which EFI files belong to wootc (%w) — "+
			"refusing to overwrite boot files we cannot prove are ours", err)
	}
	for _, rel := range relPaths {
		full := filepath.Join(espPath, rel)
		if _, err := os.Stat(full); err != nil {
			continue // absent: nothing to clobber
		}
		if owned[normalizeESPPath(rel)] {
			continue // ours from a previous install: a reinstall may replace it
		}
		return fmt.Errorf("this PC's EFI boot partition already contains %s, which wootc did not "+
			"put there — it belongs to another operating system. Installing would make that "+
			"system unbootable, so wootc stopped before changing anything", rel)
	}
	return nil
}

// recordESPOwnership claims the given paths, merging with anything already
// claimed. Written after a successful copy so an aborted install never claims
// files it did not write.
func recordESPOwnership(espPath string, relPaths []string) error {
	owned, err := readESPOwnership(espPath)
	if err != nil {
		return err
	}
	for _, rel := range relPaths {
		owned[normalizeESPPath(rel)] = true
	}
	if err := os.MkdirAll(filepath.Dir(espManifestPath(espPath)), 0o755); err != nil {
		return err
	}
	var b strings.Builder
	b.WriteString("# Files on this EFI partition written by wootc.\n")
	b.WriteString("# wootc will replace these on reinstall and refuse to touch anything else.\n")
	for p := range owned {
		b.WriteString(p + "\n")
	}
	return os.WriteFile(espManifestPath(espPath), []byte(b.String()), 0o644)
}
