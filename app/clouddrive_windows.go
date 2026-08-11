//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Cloud-drive detection (#66).
//
// OneDrive, Google Drive and Dropbox account for virtually all consumer cloud
// storage. wootc needs to detect them during Phase 1 while Windows is running:
// two live in regular directories that the User Data Bridge can bind, but one
// (Google Drive for desktop) is a virtual drive letter produced by DriveFS at
// runtime. From Linux, reading the physical disk offline, G: does not exist.
//
// The manifest written here is consumed at two points:
//   1. Phase 1 GUI: show a pre-migration disclosure of how much data lives
//      where, so the user knows what to expect.
//   2. Phase 2 bridge: detect that the provider exists so first-boot rclone
//      provisioning knows which remotes to create. Without this step the
//      Phase-2 bridge never finds Google Drive at all, because there is no
//      profile directory to bind — it is a virtual filesystem that lives only
//      while DriveFS is running.

// CloudDrive is one detected cloud-storage provider or account.
type CloudDrive struct {
	Provider     string `json:"provider"`     // "onedrive" | "googledrive" | "dropbox"
	Account      string `json:"account"`      // email or descriptive label (OneDrive: "Personal" / "Business1")
	RootPath     string `json:"rootPath"`     // filesystem path or drive letter (G:)
	VirtualDrive bool   `json:"virtualDrive"` // true when the root lives only at runtime (Google Drive)
	LocalBytes   int64  `json:"localBytes"`   // -1 when unknown; 0 means fully cloud-only
	CloudOnly    int    `json:"cloudOnly"`    // count of dehydrated/reparse-only entries
	Note         string `json:"note,omitempty"`
}

// ── Detection ────────────────────────────────────────────────────────────────

// detectOneDrive reads HKCU\Software\Microsoft\OneDrive\Accounts\* and returns
// one CloudDrive per account that has a non-empty UserFolder value.
func detectOneDrive() []CloudDrive {
	baseKey := `HKCU:\Software\Microsoft\OneDrive\Accounts`
	names := enumerateSubkeyNames(baseKey)
	if len(names) == 0 {
		return nil
	}
	var drives []CloudDrive
	for _, name := range names {
		props := readRegistryProperties(baseKey + `\` + name)
		userFolder, ok := props["UserFolder"]
		if !ok || userFolder == "" {
			continue
		}
		// UserFolder is commonly REG_EXPAND_SZ — expand environment vars.
		userFolder = os.ExpandEnv(userFolder)
		cd := CloudDrive{
			Provider:     "onedrive",
			Account:      name,
			RootPath:     userFolder,
			VirtualDrive: false,
			LocalBytes:   dirSizeBytes(userFolder),
			CloudOnly:    countCloudOnly(userFolder),
		}
		if cd.CloudOnly > 0 && cd.LocalBytes <= 0 {
			cd.Note = "All content is cloud-only; a network sync is needed"
		}
		drives = append(drives, cd)
	}
	return drives
}

// detectGoogleDrive reads HKLM and HKCU \Software\Google\DriveFS for the
// Share mount point. The default streaming location is G: — a virtual drive
// letter exported by DriveFS at runtime, not a real NTFS volume.
func detectGoogleDrive() []CloudDrive {
	var drives []CloudDrive

	// Google Drive exposes a single "Share" mount point. The hive that
	// contains it depends on the install type (per-user vs. per-machine).
	hives := []string{
		`HKLM:\Software\Google\DriveFS`,
		`HKCU:\Software\Google\DriveFS`,
	}
	for _, hive := range hives {
		props := readRegistryProperties(hive)
		share, ok := props["Share"]
		if !ok || share == "" {
			continue
		}
		// Share is something like "G:" — a drive letter, not a directory.
		// Even when it names a letter, confirm this is a virtual drive by
		// checking whether it resolves to a real NTFS volume.
		virtualDrive := isVirtualDriveLetter(share)

		cd := CloudDrive{
			Provider:     "googledrive",
			Account:      "Google Drive",
			RootPath:     share,
			VirtualDrive: virtualDrive,
			LocalBytes:   -1,
		}
		if virtualDrive {
			cd.Note = "Virtual drive — content is only available while Drive for desktop is running. Requires sign-in on Linux."
			// When it is a virtual drive, we cannot read it directly —
			// Get-PSDrive (or the native Windows API that backs it) needs the
			// provider, and files look like reparse points. Try a PowerShell
			// measurement anyway; it will succeed for local copies.
			cd.LocalBytes = dirSizePS(share)
			cd.CloudOnly = countCloudOnly(share + `\`)
		} else {
			cd.LocalBytes = dirSizeBytes(share)
		}
		drives = append(drives, cd)
		return drives // one entry per machine
	}

	// Fallback: the user might have Drive installed but never signed in, or
	// installed in a nonstandard location. Check for the DriveFS executable.
	if out, err := runPowerShellOutput(
		`$p = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\GoogleDriveFS.exe' -ErrorAction SilentlyContinue)
if ($p) { Write-Output $p.'(Default)' }`); err == nil && strings.TrimSpace(out) != "" {
		drives = append(drives, CloudDrive{
			Provider:     "googledrive",
			Account:      "Google Drive",
			RootPath:     "",
			VirtualDrive: true,
			LocalBytes:   -1,
			Note:         "Google Drive is installed but no mount point was found in the registry. It may need to be signed in.",
		})
	}
	return drives
}

// detectDropbox reads %APPDATA%\Dropbox\info.json and %LOCALAPPDATA%\Dropbox\info.json
// for personal and business account paths.
func detectDropbox() []CloudDrive {
	var drives []CloudDrive

	infoPaths := []string{
		filepath.Join(os.Getenv("APPDATA"), "Dropbox", "info.json"),
		filepath.Join(os.Getenv("LOCALAPPDATA"), "Dropbox", "info.json"),
	}

	seenPaths := map[string]bool{}
	for _, p := range infoPaths {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		// info.json is keyed by account type: "personal", "business".
		var raw map[string]json.RawMessage
		if err := json.Unmarshal(data, &raw); err != nil {
			continue
		}
		for accountType, rawEntry := range raw {
			var entry struct {
				Path string `json:"path"`
				Host uint64 `json:"host"` // Dropbox internal host ID
			}
			if err := json.Unmarshal(rawEntry, &entry); err != nil {
				continue
			}
			if entry.Path == "" {
				continue
			}
			// Normalize separators; info.json sometimes uses forward slashes.
			entry.Path = filepath.Clean(strings.ReplaceAll(entry.Path, "/", `\`))
			if seenPaths[entry.Path] {
				continue
			}
			seenPaths[entry.Path] = true

			acctLabel := accountType
			if entry.Host != 0 {
				acctLabel = fmt.Sprintf("%s:%d", accountType, entry.Host)
			}
			cd := CloudDrive{
				Provider:     "dropbox",
				Account:      acctLabel,
				RootPath:     entry.Path,
				VirtualDrive: false,
				LocalBytes:   dirSizeBytes(entry.Path),
				CloudOnly:    countCloudOnly(entry.Path),
			}
			if cd.CloudOnly > 0 && cd.LocalBytes <= 0 {
				cd.Note = "All content is cloud-only (Smart Sync). A network sync is needed."
			}
			drives = append(drives, cd)
		}
	}
	return drives
}

// ── Collection entry point ───────────────────────────────────────────────────

// collectCloudDrives detects all cloud-storage providers and writes the
// manifest to C:\wootc\cloud-drives.json.
func collectCloudDrives() error {
	var drives []CloudDrive
	drives = append(drives, detectOneDrive()...)
	drives = append(drives, detectGoogleDrive()...)
	drives = append(drives, detectDropbox()...)

	if len(drives) == 0 {
		// Nothing detected — still write an empty manifest so the Phase-2
		// bridge knows the scan ran and found nothing, rather than guessing
		// whether the scan itself failed.
		drives = []CloudDrive{}
	}

	manifest := struct {
		Drives []CloudDrive `json:"drives"`
	}{Drives: drives}

	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(wootcDir(), "cloud-drives.json"), data, 0o644)
}

// recordCloudDrives is the install-step entry point. Failure is never fatal:
// cloud drives are supplementary; the install still succeeds if detection
// fails, and the Phase-2 bridge can still run rclone interactively.
func recordCloudDrives() {
	if err := collectCloudDrives(); err != nil {
		fmt.Fprintf(os.Stderr, "wootc: cloud-drive detection failed (%v) — "+
			"the bridge will not pre-provision rclone remotes\n", err)
	}
}

// ── Drive-type heuristics ────────────────────────────────────────────────────

// isVirtualDriveLetter reports whether a path like "G:" or "G:\" is a virtual
// DriveFS mount (not a real NTFS volume). DriveFS volumes report themselves as
// type "Google Drive File Stream" in Get-Volume.
//
// Returns false when the drive letter does not exist at all (conservative).
func isVirtualDriveLetter(path string) bool {
	letter := strings.TrimRight(strings.TrimSpace(path), `:\`)
	if len(letter) != 1 {
		return false
	}
	out, err := runPowerShellOutput(fmt.Sprintf(
		`$v = Get-Volume -DriveLetter %s -ErrorAction SilentlyContinue
if ($v) { Write-Output $v.FileSystemType }
else { Write-Output 'none' }`, letter))
	if err != nil {
		return false
	}
	fsType := strings.TrimSpace(out)
	if fsType == "none" || fsType == "" {
		return false
	}
	// DriveFS is the Google Drive File Stream filesystem. A real NTFS/FAT32
	// volume is not virtual.
	virtualTypes := map[string]bool{
		"Google Drive File Stream": true,
		"DriveFS":                  true,
		"dfsfuse":                  true,
	}
	return virtualTypes[fsType]
}

// dirSizePS uses PowerShell to measure a directory (works for virtual
// drives where os.Stat / filepath.Walk on "G:\" from Go may fail).
func dirSizePS(dir string) int64 {
	out, err := runPowerShellOutput(fmt.Sprintf(
		`$d = %q
if (-not (Test-Path -LiteralPath $d)) { Write-Output -1; exit 0 }
$total = (Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
if (-not $total) { Write-Output -1 } else { Write-Output $total }`, dir))
	if err != nil {
		return -1
	}
	n, err := strconv.ParseInt(strings.TrimSpace(out), 10, 64)
	if err != nil {
		return -1
	}
	return n
}

// dirSizeBytes returns the total bytes recursively in a directory, or -1 when
// the directory does not exist or cannot be read. Uses os.Walk for real paths.
func dirSizeBytes(path string) int64 {
	if path == "" {
		return -1
	}
	// Strip trailing backslash+colon for "G:\" style entries.
	path = strings.TrimRight(path, `:\`)
	if len(path) == 1 && path[0] >= 'A' && path[0] <= 'Z' {
		// A bare drive letter — walk from root.
		path = path + `:\`
	}

	var total int64
	_ = filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // skip unreadable entries
		}
		if info != nil && !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	if total == 0 {
		return -1
	}
	return total
}
