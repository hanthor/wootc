//go:build !windows

package main

// Cloud-drive detection (#66) is Windows-only: OneDrive, Google Drive and
// Dropbox are detected from the live Windows install during Phase 1. On
// non-Windows dev builds there is nothing to detect; the stub keeps the
// install step list compilable and a no-op, matching the *_other.go pattern
// (recordKnownFolders, collectLook, etc.).
func recordCloudDrives() {}
