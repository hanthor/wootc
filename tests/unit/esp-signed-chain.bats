#!/usr/bin/env bats
# esp-signed-chain.bats — verify ESP signed-chain refresh and bootloader sync (#333).
# Pins:
#   1. wootc-esp-sync.path watches /usr/lib/bootupd/updates/EFI.json and triggers wootc-esp-sync.service
#   2. module-setup.sh and deploy.sh stage and enable wootc-esp-sync.path
#   3. deploy.sh mirrors the ESP manifest to /etc/wootc/esp-manifest
#   4. wootc-esp-sync discovers bootupd/classic updates, respects the D1 ownership rule,
#      gates on SBAT generation and firmware db CAs, archives to EFI/wootc/archive/<sha>/,
#      and writes GRUB first and shim last.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SYNC_BIN="$REPO_ROOT/payload/migration/wootc-esp-sync"
    PATH_UNIT="$REPO_ROOT/payload/migration/wootc-esp-sync.path"
    SERVICE_UNIT="$REPO_ROOT/payload/migration/wootc-esp-sync.service"
    MODULE_SETUP="$REPO_ROOT/payload/deployer/module-setup.sh"
    DEPLOY_SH="$REPO_ROOT/payload/deployer/deploy.sh"

    TMP_DIR="$(mktemp -d)"
    MOCK_ESP="$TMP_DIR/esp"
    MOCK_BOOT="$TMP_DIR/boot"
    MOCK_BOOTUPD="$TMP_DIR/bootupd"
    MOCK_EFIVARS="$TMP_DIR/efivars"
    MOCK_CONF="$TMP_DIR/host-esp.conf"
    MOCK_MANIFEST="$TMP_DIR/esp-manifest"
    MOCK_CMDLINE="$TMP_DIR/cmdline"

    mkdir -p "$MOCK_ESP/EFI/wootc" "$MOCK_ESP/EFI/fedora" "$MOCK_BOOT" "$MOCK_BOOTUPD" "$MOCK_EFIVARS"
    echo "root=UUID=1111 loop=/wootc/disks/root.disk wootc.host_uuid=2222" > "$MOCK_CMDLINE"
    echo "HOST_ESP_UUID=1234-ABCD" > "$MOCK_CONF"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "wootc-esp-sync.path watches bootupd EFI.json and triggers service" {
    [ -f "$PATH_UNIT" ]
    grep -q 'PathChanged=/usr/lib/bootupd/updates/EFI.json' "$PATH_UNIT"
    grep -q 'Unit=wootc-esp-sync.service' "$PATH_UNIT"
    grep -q 'ConditionPathExists=/etc/wootc/host-esp.conf' "$PATH_UNIT"
    grep -q 'WantedBy=multi-user.target' "$PATH_UNIT"
}

@test "wootc-esp-sync.service is conditioned on host-esp.conf" {
    [ -f "$SERVICE_UNIT" ]
    grep -q 'ConditionPathExists=/etc/wootc/host-esp.conf' "$SERVICE_UNIT"
    grep -q 'ExecStart=/var/usrlocal/bin/wootc-esp-sync' "$SERVICE_UNIT"
}

@test "module-setup.sh packages wootc-esp-sync.path" {
    grep -q 'inst /usr/lib/wootc/migration/wootc-esp-sync.path' "$MODULE_SETUP"
    grep -q 'inst /usr/lib/wootc/migration/wootc-esp-sync.service' "$MODULE_SETUP"
    grep -q 'inst /usr/lib/wootc/migration/wootc-esp-sync' "$MODULE_SETUP"
}

@test "deploy.sh installs and enables wootc-esp-sync.path" {
    grep -q 'install -m644 /usr/lib/wootc/migration/wootc-esp-sync.path' "$DEPLOY_SH"
    grep -q 'ln -sf \.\./wootc-esp-sync.path' "$DEPLOY_SH"
    grep -q 'multi-user.target.wants/wootc-esp-sync.path' "$DEPLOY_SH"
}

@test "deploy.sh mirrors ESP manifest to /etc/wootc/esp-manifest" {
    grep -q 'cp "$man_cand" "$DEPLOY_ROOT/etc/wootc/esp-manifest"' "$DEPLOY_SH"
}

@test "wootc-esp-sync refreshes signed chain from bootupd updates" {
    # Staged installed files
    echo "old-shim" > "$MOCK_ESP/EFI/fedora/shimx64.efi"
    echo "old-grub" > "$MOCK_ESP/EFI/fedora/grubx64.efi"
    cat << 'EOF' > "$MOCK_MANIFEST"
# wootc manifest
efi/fedora/shimx64.efi
efi/fedora/grubx64.efi
efi/wootc/phase2-vmlinuz
efi/wootc/phase2-initramfs.img
EOF

    # Kernel setup
    echo "kernel-v1" > "$MOCK_BOOT/vmlinuz-6.6.0"
    echo "initrd-v1" > "$MOCK_BOOT/initramfs-6.6.0.img"

    # Candidate files in bootupd
    mkdir -p "$MOCK_BOOTUPD/EFI/fedora"
    echo "new-shim" > "$MOCK_BOOTUPD/EFI/fedora/shimx64.efi"
    echo "new-grub" > "$MOCK_BOOTUPD/EFI/fedora/grubx64.efi"

    ORIG_SHA=$(sha256sum "$MOCK_ESP/EFI/fedora/shimx64.efi" | awk '{print $1}')

    WOOTC_ESP_DIR="$MOCK_ESP" \
    WOOTC_BOOT_DIR="$MOCK_BOOT" \
    WOOTC_BOOTUPD_DIR="$MOCK_BOOTUPD" \
    WOOTC_SYSFS_EFIVARS="$MOCK_EFIVARS" \
    WOOTC_ESP_MANIFEST="$MOCK_MANIFEST" \
    WOOTC_CMDLINE="$MOCK_CMDLINE" \
    bash "$SYNC_BIN"

    # Check that installed files were updated
    [ "$(cat "$MOCK_ESP/EFI/fedora/shimx64.efi")" = "new-shim" ]
    [ "$(cat "$MOCK_ESP/EFI/fedora/grubx64.efi")" = "new-grub" ]

    # Check archive was created with original sha
    [ -d "$MOCK_ESP/EFI/wootc/archive/$ORIG_SHA" ]
    [ "$(cat "$MOCK_ESP/EFI/wootc/archive/$ORIG_SHA/shimx64.efi")" = "old-shim" ]
    [ "$(cat "$MOCK_ESP/EFI/wootc/archive/$ORIG_SHA/grubx64.efi")" = "old-grub" ]
}

@test "wootc-esp-sync respects D1 rule and skips foreign unmanifested files" {
    echo "foreign-shim" > "$MOCK_ESP/EFI/fedora/shimx64.efi"
    echo "foreign-grub" > "$MOCK_ESP/EFI/fedora/grubx64.efi"
    cat << 'EOF' > "$MOCK_MANIFEST"
# manifest without EFI/fedora
efi/wootc/phase2-vmlinuz
EOF

    mkdir -p "$MOCK_BOOTUPD/EFI/fedora"
    echo "new-shim" > "$MOCK_BOOTUPD/EFI/fedora/shimx64.efi"
    echo "new-grub" > "$MOCK_BOOTUPD/EFI/fedora/grubx64.efi"

    echo "kernel-v1" > "$MOCK_BOOT/vmlinuz-6.6.0"
    echo "initrd-v1" > "$MOCK_BOOT/initramfs-6.6.0.img"

    WOOTC_ESP_DIR="$MOCK_ESP" \
    WOOTC_BOOT_DIR="$MOCK_BOOT" \
    WOOTC_BOOTUPD_DIR="$MOCK_BOOTUPD" \
    WOOTC_SYSFS_EFIVARS="$MOCK_EFIVARS" \
    WOOTC_ESP_MANIFEST="$MOCK_MANIFEST" \
    WOOTC_CMDLINE="$MOCK_CMDLINE" \
    bash "$SYNC_BIN"

    # Foreign files remain untouched
    [ "$(cat "$MOCK_ESP/EFI/fedora/shimx64.efi")" = "foreign-shim" ]
    [ "$(cat "$MOCK_ESP/EFI/fedora/grubx64.efi")" = "foreign-grub" ]
}

@test "wootc-esp-sync refuses SBAT downgrade" {
    cat << 'EOF' > "$MOCK_ESP/EFI/fedora/shimx64.efi"
sbat,1,SBAT
shim,4,RedHat,shim,16
EOF
    echo "old-grub" > "$MOCK_ESP/EFI/fedora/grubx64.efi"

    cat << 'EOF' > "$MOCK_MANIFEST"
efi/fedora/shimx64.efi
efi/fedora/grubx64.efi
EOF

    mkdir -p "$MOCK_BOOTUPD/EFI/fedora"
    cat << 'EOF' > "$MOCK_BOOTUPD/EFI/fedora/shimx64.efi"
sbat,1,SBAT
shim,3,RedHat,shim,15
EOF
    echo "new-grub" > "$MOCK_BOOTUPD/EFI/fedora/grubx64.efi"

    echo "kernel-v1" > "$MOCK_BOOT/vmlinuz-6.6.0"
    echo "initrd-v1" > "$MOCK_BOOT/initramfs-6.6.0.img"

    WOOTC_ESP_DIR="$MOCK_ESP" \
    WOOTC_BOOT_DIR="$MOCK_BOOT" \
    WOOTC_BOOTUPD_DIR="$MOCK_BOOTUPD" \
    WOOTC_SYSFS_EFIVARS="$MOCK_EFIVARS" \
    WOOTC_ESP_MANIFEST="$MOCK_MANIFEST" \
    WOOTC_CMDLINE="$MOCK_CMDLINE" \
    bash "$SYNC_BIN"

    # Refused downgrade: installed shim remains generation 4
    grep -q 'shim,4' "$MOCK_ESP/EFI/fedora/shimx64.efi"
}

@test "wootc-esp-sync gates on CA intersection when Secure Boot is active" {
    # Active Secure Boot efivar: 4 byte attr + 0x01
    printf '\x07\x00\x00\x00\x01' > "$MOCK_EFIVARS/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    
    # Firmware db trusting only 2023 CA
    cat << 'EOF' > "$MOCK_EFIVARS/db-d719b2cb-3d3a-4596-a3bc-dad00e67656f"
Microsoft UEFI CA 2023
EOF

    # Installed shim signed by 2011
    cat << 'EOF' > "$MOCK_ESP/EFI/fedora/shimx64.efi"
Microsoft Corporation UEFI CA 2011
EOF
    echo "old-grub" > "$MOCK_ESP/EFI/fedora/grubx64.efi"

    cat << 'EOF' > "$MOCK_MANIFEST"
efi/fedora/shimx64.efi
efi/fedora/grubx64.efi
EOF

    # Candidate shim signed ONLY by 2011 (no intersection with db 2023)
    mkdir -p "$MOCK_BOOTUPD/EFI/fedora"
    cat << 'EOF' > "$MOCK_BOOTUPD/EFI/fedora/shimx64.efi"
Microsoft Corporation UEFI CA 2011
EOF
    echo "new-grub" > "$MOCK_BOOTUPD/EFI/fedora/grubx64.efi"

    echo "kernel-v1" > "$MOCK_BOOT/vmlinuz-6.6.0"
    echo "initrd-v1" > "$MOCK_BOOT/initramfs-6.6.0.img"

    WOOTC_ESP_DIR="$MOCK_ESP" \
    WOOTC_BOOT_DIR="$MOCK_BOOT" \
    WOOTC_BOOTUPD_DIR="$MOCK_BOOTUPD" \
    WOOTC_SYSFS_EFIVARS="$MOCK_EFIVARS" \
    WOOTC_ESP_MANIFEST="$MOCK_MANIFEST" \
    WOOTC_CMDLINE="$MOCK_CMDLINE" \
    bash "$SYNC_BIN"

    # Candidate refused due to no CA intersection with db
    [ "$(cat "$MOCK_ESP/EFI/fedora/grubx64.efi")" = "old-grub" ]
}

@test "wootc-esp-sync refreshes signed chain from classic /boot/efi" {
    echo "old-shim" > "$MOCK_ESP/EFI/fedora/shimx64.efi"
    echo "old-grub" > "$MOCK_ESP/EFI/fedora/grubx64.efi"
    cat << 'EOF' > "$MOCK_MANIFEST"
efi/fedora/shimx64.efi
efi/fedora/grubx64.efi
EOF

    echo "kernel-v1" > "$MOCK_BOOT/vmlinuz-6.6.0"
    echo "initrd-v1" > "$MOCK_BOOT/initramfs-6.6.0.img"

    MOCK_CLASSIC="$TMP_DIR/boot_efi"
    mkdir -p "$MOCK_CLASSIC/EFI/fedora"
    echo "classic-shim" > "$MOCK_CLASSIC/EFI/fedora/shimx64.efi"
    echo "classic-grub" > "$MOCK_CLASSIC/EFI/fedora/grubx64.efi"

    WOOTC_ESP_DIR="$MOCK_ESP" \
    WOOTC_BOOT_DIR="$MOCK_BOOT" \
    WOOTC_BOOTUPD_DIR="$TMP_DIR/nonexistent-bootupd" \
    WOOTC_BOOT_EFI_DIR="$MOCK_CLASSIC" \
    WOOTC_SYSFS_EFIVARS="$MOCK_EFIVARS" \
    WOOTC_ESP_MANIFEST="$MOCK_MANIFEST" \
    WOOTC_CMDLINE="$MOCK_CMDLINE" \
    bash "$SYNC_BIN"

    [ "$(cat "$MOCK_ESP/EFI/fedora/shimx64.efi")" = "classic-shim" ]
    [ "$(cat "$MOCK_ESP/EFI/fedora/grubx64.efi")" = "classic-grub" ]
}

@test "wootc-esp-sync succeeds when candidate CA intersects firmware db" {
    printf '\x07\x00\x00\x00\x01' > "$MOCK_EFIVARS/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    cat << 'EOF' > "$MOCK_EFIVARS/db-d719b2cb-3d3a-4596-a3bc-dad00e67656f"
Microsoft UEFI CA 2023
EOF

    cat << 'EOF' > "$MOCK_ESP/EFI/fedora/shimx64.efi"
Microsoft Corporation UEFI CA 2011
EOF
    echo "old-grub" > "$MOCK_ESP/EFI/fedora/grubx64.efi"

    cat << 'EOF' > "$MOCK_MANIFEST"
efi/fedora/shimx64.efi
efi/fedora/grubx64.efi
EOF

    mkdir -p "$MOCK_BOOTUPD/EFI/fedora"
    cat << 'EOF' > "$MOCK_BOOTUPD/EFI/fedora/shimx64.efi"
Microsoft Corporation UEFI CA 2011
Microsoft UEFI CA 2023
EOF
    echo "new-grub" > "$MOCK_BOOTUPD/EFI/fedora/grubx64.efi"

    echo "kernel-v1" > "$MOCK_BOOT/vmlinuz-6.6.0"
    echo "initrd-v1" > "$MOCK_BOOT/initramfs-6.6.0.img"

    WOOTC_ESP_DIR="$MOCK_ESP" \
    WOOTC_BOOT_DIR="$MOCK_BOOT" \
    WOOTC_BOOTUPD_DIR="$MOCK_BOOTUPD" \
    WOOTC_SYSFS_EFIVARS="$MOCK_EFIVARS" \
    WOOTC_ESP_MANIFEST="$MOCK_MANIFEST" \
    WOOTC_CMDLINE="$MOCK_CMDLINE" \
    bash "$SYNC_BIN"

    # Succeeded because 2023 is present in both candidate and db
    [ "$(cat "$MOCK_ESP/EFI/fedora/grubx64.efi")" = "new-grub" ]
}
