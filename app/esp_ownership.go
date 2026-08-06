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

// wootcGrubMarker identifies a grub.cfg written by wootc, so reinstalls can
// overwrite it while a real Linux distro's config is protected. Declared here
// rather than in the Windows-only installer because the ownership logic (and
// its tests) must build everywhere.
const wootcGrubMarker = "# wootc deployer"

// wootcGrubOwnership is the marker family every wootc grub.cfg writer shares.
// wootc writes EFI\fedora\grub.cfg from THREE places, each with its own
// header comment:
//   - this app:            "# wootc deployer ..."
//   - setup-wootc.ps1:     "# wootc first-boot installer menu" / "# wootc deployer - ..."
//   - deploy.sh (Phase 2): "# wootc Phase 2 — boot installed system ..." and
//     "# wootc Phase 2 (composefs) ..."
// Matching only the first refused wootc's own post-deploy ESP: a user who
// completed a deploy and later reinstalled got "belongs to another operating
// system" from the very files wootc wrote (GUI cell, run 31076749824). A
// genuine Fedora/RHEL grub.cfg contains no "# wootc" comment at all, so the
// family prefix keeps the guard's teeth against real dual-boot installs.
const wootcGrubOwnership = "# wootc"

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

// isOwnNamespace reports whether a path lives in a directory only wootc ever
// writes. EFI\wootc is ours by definition — nothing else puts files there — so
// guarding it refuses our OWN reinstalls. The first version of this guard did
// exactly that and blocked el10-gnome-win11ent on
// "EFI\wootc\deployer-initramfs.img ... belongs to another operating system",
// which would equally have blocked any real user reinstalling wootc.
//
// Only SHARED vendor directories (EFI\fedora) need ownership proof.
func isOwnNamespace(rel string) bool {
	return strings.HasPrefix(normalizeESPPath(rel), "efi/wootc/")
}

// ownsFedoraNamespace reports whether the EFI\fedora tree was staged by wootc.
// An older wootc predating the manifest still left its marker in grub.cfg, so
// this keeps upgrades working without weakening the guard against a real
// Fedora/RHEL install (whose grub.cfg has no such marker). The match is the
// shared "# wootc" marker family, NOT only this app's own header — the
// deployer rewrites this file with its Phase-2 menu on every completed
// deploy, and a reinstall must recognize that as ours too.
func ownsFedoraNamespace(espPath string) bool {
	data, err := os.ReadFile(filepath.Join(espPath, "EFI", "fedora", "grub.cfg"))
	return err == nil && strings.Contains(string(data), wootcGrubOwnership)
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
	fedoraIsOurs := ownsFedoraNamespace(espPath)
	for _, rel := range relPaths {
		full := filepath.Join(espPath, rel)
		if _, err := os.Stat(full); err != nil {
			continue // absent: nothing to clobber
		}
		if isOwnNamespace(rel) {
			continue // our own directory; nothing else writes there
		}
		if owned[normalizeESPPath(rel)] {
			continue // ours from a previous install: a reinstall may replace it
		}
		if fedoraIsOurs {
			continue // an older wootc staged this tree (marker in grub.cfg)
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
