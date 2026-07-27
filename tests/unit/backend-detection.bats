#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    DEPLOY="${DEPLOY:-$REPO_ROOT/payload/deployer/deploy.sh}"
    E2E="${E2E:-$REPO_ROOT/tests/e2e/run-e2e.sh}"
    PS1="${PS1:-$REPO_ROOT/tests/e2e/setup-wootc.ps1}"
}

@test "deployer accepts auto before image backend detection" {
    run awk '
        /case "\$BOOTLOADER" in/ { validation = NR; accepts_auto = ($0 ~ /grub2\|systemd\|auto/) }
        /if \[\[ "\$COMPOSEFS" == auto \|\| "\$BOOTLOADER" == auto \]\]/ { detection = NR }
        END { exit !(validation && accepts_auto && detection && validation < detection) }
    ' "$DEPLOY"
    [ "$status" -eq 0 ]
}

@test "E2E and Windows setup pass auto through by default" {
    run grep -F 'E2E_BOOTLOADER="${WOOTC_E2E_BOOTLOADER:-auto}"' "$E2E"
    [ "$status" -eq 0 ]

    run grep -F '[ValidateSet("grub2", "systemd", "auto")]' "$PS1"
    [ "$status" -eq 0 ]

    run grep -F '[string]$Bootloader = "auto"' "$PS1"
    [ "$status" -eq 0 ]
}

@test "backend detection falls back to safe defaults when the probe fails or is ambiguous" {
    # Contract since 95b0ab5/2d76cce: a hung or failed image probe must NOT
    # abort the deploy (that lost completed installs on flaky podman). It is
    # bounded by a timeout and falls back to ostree/grub2 + SEALED=1 with a
    # loud WARN; an unrecognized backend signal likewise defaults with a WARN.
    # The probe is still bounded by a timeout — but 30s was a timeout on a PULL,
    # not on an inspection (see the acquire-before-inspect test below), so the
    # contract is "bounded", not "bounded at 30".
    run grep -E 'if ! DETECT="\$\(timeout [0-9]+ podman run' "$DEPLOY"
    [ "$status" -eq 0 ]

    run grep -F 'falling back to default backend (ostree/grub2, ext4 sealed)' "$DEPLOY"
    [ "$status" -eq 0 ]

    run grep -F 'BACKEND=unknown' "$DEPLOY"
    [ "$status" -eq 0 ]

    # An image with neither bootupd-managed grub nor systemd-boot (Arch/Debian
    # bootc images ship no bootupd) must still deploy, not abort: ostree/grub2
    # plus --generic-image so bootc skips the bootupd requirement.
    run grep -F 'no bootupd and no systemd-boot' "$DEPLOY"
    [ "$status" -eq 0 ]

    run grep -F 'GENERIC_IMAGE=1' "$DEPLOY"
    [ "$status" -eq 0 ]
}

@test "current bootupd versioned EFI layout is recognized as ostree" {
    grep -Fq 'test -f /usr/lib/bootupd/updates/EFI.json' "$DEPLOY"
    grep -Fq 'find /usr/lib/efi/grub2 -type f -name grubx64.efi' "$DEPLOY"
    grep -Fq 'find /usr/lib/efi/shim -type f -name shimx64.efi' "$DEPLOY"
}

@test "ESP staging supports the current versioned shim and GRUB layout" {
    grep -Fq 'find "$DEPLOY_ROOT/usr/lib/efi/grub2"' "$DEPLOY"
    grep -Fq '*/EFI/$vendor_dir/shimx64.efi' "$DEPLOY"
    grep -Fq '*/EFI/$TARGET_VENDOR/mmx64.efi' "$DEPLOY"
    run grep -nE '^[^#]*dirname.*TARGET_GRUB' "$DEPLOY"
    [ "$status" -ne 0 ]
}

@test "ESP staging logs every selected source and fails closed" {
    grep -Fq 'ESP source kernel=${KERNEL_SRC:-missing}' "$DEPLOY"
    grep -Fq 'ESP source initramfs=${INITRD_SRC:-missing}' "$DEPLOY"
    grep -Fq 'ESP source shim=${TARGET_SHIM:-missing}' "$DEPLOY"
    grep -Fq 'ESP source grub=${TARGET_GRUB:-missing}' "$DEPLOY"
    local fail_line exit_line
    fail_line=$(grep -n 'Phase-2 ESP sync failed' "$DEPLOY" | tail -1 | cut -d: -f1)
    exit_line=$(awk -v start="$fail_line" 'NR > start && /exit 1/ { print NR; exit }' "$DEPLOY")
    [ -n "$fail_line" ] && [ -n "$exit_line" ]
    [ "$exit_line" -le $((fail_line + 8)) ]
}

@test "initramfs regen KVER comes from the module tree that owns vmlinuz" {
    # bluefin:lts ships TWO /usr/lib/modules trees: 6.12.0-225 (stripped
    # leftover, no vmlinuz) and 6.12.0-233 (bootable). `ls | head -1` picked
    # 225, dracut built a 225-module initramfs, the 233 kernel booted it, and
    # not one storage driver could load — 60s of "Present devices: none" and
    # an emergency shell, with no error anywhere. The pick must require
    # vmlinuz and take the highest such version.
    grep -Fq '[[ -f "$d/vmlinuz" ]] && basename "$d"' "$DEPLOY"
    run grep -nE 'KVER=\$\(ls [^)]*head -1\)' "$DEPLOY"
    [ "$status" -ne 0 ]
}

@test "deploy.sh uses no binaries absent from the initramfs closure" {
    # $(dirname ...) killed every deploy at t=33s under set -e — the
    # initramfs has no dirname (run 20260723T1331). Path math must use
    # parameter expansion; add to this list anything else the closure lacks.
    local dep="$REPO_ROOT/payload/deployer/deploy.sh"
    for missing in dirname; do
        run grep -nE "^[^#]*\\\$\\($missing " "$dep"
        [ "$status" -ne 0 ]
    done
}

@test "filesystem defaults: xfs unsealed, ext4 sealed (btrfs blocked on #35)" {
    # xfs is the product default; a sealed rootfs needs fs-verity, which xfs
    # lacks. ext4 is the PROVEN sealed fallback (29/29 green). btrfs also has
    # fs-verity but the ostree Phase-2 boot cannot mount it yet (#35), so it
    # stays opt-in via wootc.filesystem=. Both xfs.ko and btrfs.ko must be in
    # the initramfs — a typeless mount tried ext4 on xfs until GH 20260724.
    local dep="$REPO_ROOT/payload/deployer/deploy.sh"
    grep -q 'read_cmdline wootc.filesystem xfs' "$dep"
    grep -q 'FILESYSTEM=ext4' "$dep"
    grep -B9 'FILESYSTEM=ext4' "$dep" | grep -q 'ROOTFS_SEALED'
    grep -q -- '--add-drivers "xfs btrfs"' "$REPO_ROOT/payload/deployer/Containerfile"
    grep -q 'xfs.ko' "$REPO_ROOT/payload/deployer/Containerfile"
}

@test "dracut regen failures report dracut's own output" {
    # Bare stderr reaches only the serial console (harness never surfaces
    # it, CI truncates it): three regen failures reported nothing but
    # exit=1. The tail must go through err/log so it also lands in the
    # persistent deployer.log.
    local dep="$REPO_ROOT/payload/deployer/deploy.sh"
    grep -q 'dracut-regen.log' "$dep"
    grep -q 'err "  dracut: \$dline"' "$dep"
}

@test "the backend probe acquires the image before inspecting it" {
    # `podman run` on a non-local image PULLS it first. A multi-GB bootc image
    # cannot land inside the probe timeout, so the probe "failed" and fell back
    # to ostree/grub2 — silently deploying composefs-native images (dakota,
    # marlin) down the ostree path with none of the branch logic running. This
    # is why the composefs axis never moved.
    grep -q 'podman image exists "$IMAGE"' "$DEPLOY"
    grep -q 'podman pull "$IMAGE"' "$DEPLOY"
    # The pull must come BEFORE the probe.
    pull_line=$(grep -n 'podman pull "\$IMAGE"' "$DEPLOY" | head -1 | cut -d: -f1)
    probe_line=$(grep -n 'DETECT="\$(timeout' "$DEPLOY" | head -1 | cut -d: -f1)
    [ "$pull_line" -lt "$probe_line" ]
    # And the fallback must say loudly that composefs was not exercised.
    grep -q 'treat any resulting pass as untested for composefs' "$DEPLOY"
}

@test "verification does not assume the ostree 3-partition layout" {
    # A composefs-native install lays down ESP + root only, so root is p2 and p3
    # NEVER appears. Confirmed from the partition table the probe now prints:
    # /dev/loop1p1 = 2G EFI System, /dev/loop1p2 = 33G Linux root (run
    # 30234854504). Waiting for p3 warned about nodes that could not exist, and
    # the LUKS open targeted a device that was not there.
    run grep -c 'VERIFY_LOOP}p3' "$DEPLOY"
    [ "$output" -eq 0 ]
    grep -q '_verify_parts\[${#_verify_parts\[@\]}-1\]' "$DEPLOY"
}

@test "a composefs deployment root is not prepared as a chroot" {
    # It is a READ-ONLY image tree with no dev/proc/sys, and its branch performs
    # no chroot — but `mount --bind` ran first and set -e killed the deployer
    # silently at t=659s, after which the harness waited out 90 minutes.
    grep -q 'skipping chroot preparation' "$DEPLOY"
    grep -q 'DEPLOY_ROOT" == \*/state/deploy/\*' "$DEPLOY"
}

@test "an image with no NTFS driver fails the deploy, not Phase 2" {
    # "Relying on the image's own NTFS support" was never checked. On EL-family
    # images (no kernel ntfs3) a failed ntfs-3g injection still produced a full
    # deploy that CANNOT boot Phase 2: el10-gnome-win10pro spent 91 minutes to
    # reach "cannot mount host NTFS rw (no ntfs3, no ntfs-3g)" and an emergency
    # shell, when the evidence existed 80 minutes earlier.
    grep -q 'checking whether the image can mount NTFS on its own' "$DEPLOY"
    grep -q 'has NO NTFS driver' "$DEPLOY"
    grep -q 'Refusing to write an unbootable deployment' "$DEPLOY"
}

@test "Phase 2 never ships without an NTFS driver" {
    # Phase 2 mounts the Windows volume to reach root.disk. EL kernels have no
    # ntfs3, so the deployment needs ntfs-3g — and when the injection step fails
    # the old code logged a WARN and carried on, producing a deployment that
    # emergency-shelled with "no ntfs3, no ntfs-3g" 91 minutes later
    # (el10-gnome-win10pro, 20260727T082625Z).
    #
    # The deployer itself always ships ntfs-3g (its Containerfile), so use it.
    grep -q "Injected the deployer's own ntfs-3g" "$DEPLOY"
    grep -q 'command -v ntfs-3g' "$DEPLOY"
    # Its shared libraries must come too, or the installed binary cannot run.
    grep -q 'ldd "\$_ntfs_src"' "$DEPLOY"
    # And with no driver available at all, refuse rather than ship it.
    grep -q 'no NTFS driver for Phase 2' "$DEPLOY"
    grep -q 'Refusing to finish a deployment that cannot boot' "$DEPLOY"
}
