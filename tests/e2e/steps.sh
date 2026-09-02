#!/usr/bin/env bash
# Code generated from payload/steps.tsv by gen-steps.py; DO NOT EDIT.

# Ordered list of installer step IDs
INSTALLER_STEPS=(
    "check-pc"
    "prepare-windows"
    "setting-up"
    "finding-files"
    "make-room"
    "download-linux"
    "download-system"
    "prepare-startup-menu"
    "prepare-linux"
    "make-bootable"
    "save-settings"
    "save-bitlocker-key"
    "inspect-apps"
    "check-signed-in-apps"
    "cloud-drives"
    "collect-look-wifi"
    "finishing-up"
)

# Ordered list of deployer phase IDs
DEPLOYER_PHASES=(
    "ntfs-mounted"
    "scratch-setup"
    "network-wait"
    "bundle-ingest"
    "registry-preflight"
    "fisherman"
    "verification"
    "reboot"
)

# Ordered list of firstboot step IDs
FIRSTBOOT_STEPS=(
    "firstboot-evidence"
)

# Allowed phase values across all owners (failure ledger, recovery verdict, telemetry)
ALL_PHASES=(
    "check-pc"
    "prepare-windows"
    "setting-up"
    "finding-files"
    "make-room"
    "download-linux"
    "download-system"
    "prepare-startup-menu"
    "prepare-linux"
    "make-bootable"
    "save-settings"
    "save-bitlocker-key"
    "inspect-apps"
    "check-signed-in-apps"
    "cloud-drives"
    "collect-look-wifi"
    "finishing-up"
    "ntfs-mounted"
    "scratch-setup"
    "network-wait"
    "bundle-ingest"
    "registry-preflight"
    "fisherman"
    "verification"
    "reboot"
    "firstboot-evidence"
)

is_valid_phase() {
    local candidate="$1"
    for p in "${ALL_PHASES[@]}"; do
        [ "$p" = "$candidate" ] && return 0
    done
    return 1
}
