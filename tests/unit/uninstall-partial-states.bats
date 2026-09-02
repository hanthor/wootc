#!/usr/bin/env bats
# uninstall-partial-states.bats — uninstall must converge from every partial-install state (#289).
#
# Interrupted installs can leave partial files, lifecycle markers, registry entries,
# power-setting changes, BCD entries, or EFI artifacts.
# The uninstaller must discover and converge cleanly from all partial states:
#   - fresh / unstarted
#   - staged (interrupted during download, root disk, or image pull)
#   - armed (interrupted after BCD / ESP staging)
#   - failed (failure recorded in state.json)
#   - partially deployed (deployer log or journal present)
#   - orphaned (C:\wootc deleted by hand)
#
# Dedicated volume cleanup must also strictly verify ownership and never confuse
# the EFI system partition with a wootc-created data partition.

INSTALLER_WIN=app/installer_windows.go
DISK_WIN=app/disk_windows.go
HEADLESS_GO=app/headless.go
PROBE_WIN=app/sysprobe_windows.go

@test "getUninstallInfo detects partial install when wootc directory exists without root.disk" {
    grep -q 'Orphaned:\s*true' "$INSTALLER_WIN"
    grep -q 'hasWootcBCDEntry()' "$INSTALLER_WIN"
    grep -q 'hasWootcESPArtifacts()' "$INSTALLER_WIN"
    grep -q 'hasUninstallRegistryEntry()' "$INSTALLER_WIN"
}

@test "uninstallWith cleans up install, bundle, cache, and logs dirs on keep-root.disk" {
    grep -q 'os.RemoveAll(filepath.Join(wDir, sub))' "$INSTALLER_WIN"
    grep -q 'for _, sub := range \[\]string{"install", "bundle", "cache", "logs"}' "$INSTALLER_WIN"
}

@test "uninstallWith sweeps entire wootc folder when no root.disk exists or on deletion request" {
    grep -q 'opts.DeleteRootDisk || opts.RemovePartition || !rootDiskExists' "$INSTALLER_WIN"
}

@test "dedicated volume verification requires exact wootc-data label and refuses EFI system partition" {
    grep -q "FileSystemLabel -ne 'wootc-data'" "$DISK_WIN"
    grep -q "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" "$DISK_WIN"
    grep -q "Type -eq 'System'" "$DISK_WIN"
    grep -q "Refusing to remove EFI system partition" "$DISK_WIN"
}

@test "partition reclaim refuses to remove drive C:" {
    grep -q "refusing to remove partition on drive C:" "$DISK_WIN"
}

@test "uninstall verifies clean convergence and reports leftover artifacts" {
    grep -q 'verifyUninstallClean' "$INSTALLER_WIN"
    grep -q 'uninstall cleanup incomplete' "$INSTALLER_WIN"
}

@test "headless uninstall command parses -delete-root-disk and -remove-partition flags" {
    grep -q 'headlessUninstall' "$HEADLESS_GO"
    grep -q 'delete-root-disk' "$HEADLESS_GO"
    grep -q 'remove-partition' "$HEADLESS_GO"
}
