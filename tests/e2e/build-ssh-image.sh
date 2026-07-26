#!/usr/bin/env bash
# Builds localhost/wootc-e2e-windows-ssh:latest — the dockurr/windows image
# with sshd baked in (key-only auth, dedicated e2e keypair) so debug
# sessions can `ssh` straight into the container instead of nesting
# `podman exec` through heredocs (a real source of quoting bugs during
# E2E debugging).
#
# Recipe: pull the base image, run it with a harmless override entrypoint,
# install+configure openssh-server in that running container, wrap the
# original entrypoint (dockurr/windows's own `tini -s /run/entry.sh`, which
# this script does NOT modify) so sshd starts alongside it, then commit the
# result as a new image. Re-run this script any time the base image updates.
#
# Usage: bash tests/e2e/build-ssh-image.sh [keyfile]
#   keyfile defaults to ~/.ssh/wootc_e2e_ed25519 (created if missing).
#
# After building, run-e2e.sh / compose.yml pick it up automatically
# (compose.yml's `image:` defaults to this tag). Connect with:
#   ssh -i ~/.ssh/wootc_e2e_ed25519 -p 2222 root@localhost
# (see compose.yml's ports: mapping for the published SSH port).

set -Eeuo pipefail

# PINNED. `:latest` moved from v6.02 to v6.03 mid-session and swtpm stopped
# starting inside the container ("Waiting for TPM emulator to launch..." then
# "ERROR: TPM socket (/tmp/swtpm.sock) not found? Disabling TPM module"),
# so dockur silently ran QEMU WITHOUT a TPM and every Windows 11 case failed the
# "missing TPM 2.0 or Secure Boot" preflight (runs 30183222185, 30188615998 —
# container.log records the version on its first line). Windows 11 requires
# TPM 2.0, so an unpinned base can break the whole matrix without a wootc change.
# Bump deliberately, after a green run, not by surprise.
BASE_IMAGE="${WOOTC_E2E_BASE_IMAGE:-docker.io/dockurr/windows:6.02}"
TARGET_IMAGE="localhost/wootc-e2e-windows-ssh:latest"
KEYFILE="${1:-$HOME/.ssh/wootc_e2e_ed25519}"
BUILDER="wootc-ssh-builder"

if [[ ! -f "$KEYFILE" ]]; then
    echo "+ generating dedicated e2e keypair at $KEYFILE"
    ssh-keygen -t ed25519 -N "" -C "wootc-e2e-debug" -f "$KEYFILE"
fi

echo "+ pulling $BASE_IMAGE"
podman pull -q "$BASE_IMAGE" >/dev/null

podman rm -f "$BUILDER" >/dev/null 2>&1 || true
echo "+ starting builder container"
podman run -d --name "$BUILDER" --entrypoint sh "$BASE_IMAGE" -c "sleep infinity"

echo "+ installing openssh-server"
podman exec "$BUILDER" sh -c "apt-get update -qq && apt-get install -y -qq openssh-server >/dev/null"
podman exec "$BUILDER" ssh-keygen -A

# ── #59: move the swtpm state off /storage ──────────────────────────────────
# dockur puts TPM state next to the firmware: boot.sh has
#   DEST="$STORAGE/${BOOT_MODE,,}"   …   --tpmstate "backend-uri=file://$DEST.tpm"
# On GitHub-hosted runners, swtpm HANGS when its state lives on the bind-mounted
# /storage (ext4 from the runner's /mnt): it runs with correct arguments, prints
# nothing, and never binds its control socket. dockur waits ~4s, gives up, and
# SILENTLY disables TPM — so Windows 11 boots without TPM 2.0 and every win11
# case fails our preflight. Proven with an A/B inside one failing container:
#   state on /storage -> timeout, no socket        (storage-fs=ext2/ext3)
#   state on /tmp     -> srwxrwx--- socket created (tmp-fs=overlayfs)
# /storage is writable, so this is not permissions; five other theories
# (dockur version, disk2 I/O, disk resize, our apt step, AppArmor) were each
# disproven by a run. See #59.
#
# Only the tpmstate URI moves. DEST still points at /storage for the pflash
# ROM/VARS, which must persist. /tmp is container-lifetime (it is part of the
# container's overlayfs, per the probe: tmp-fs=overlayfs), so TPM state survives
# guest reboots within a run (Phase 1 -> Phase 2); it was never carried in the
# base-image snapshots anyway.
#
# /tmp specifically, NOT /run: the A/B measured /tmp binding a socket in the
# failing container, and a first attempt using /run still failed (run
# 30197227495 — patch applied, swtpm still never bound). Use the path that was
# actually proven.
echo "+ patching dockur boot.sh to keep swtpm state off /storage (#59)"
podman exec "$BUILDER" sh -c \
    "sed -i 's#backend-uri=file://\$DEST.tpm#backend-uri=file:///tmp/wootc-swtpm.state#' /run/boot.sh && \
     grep -n 'tpmstate' /run/boot.sh"

# ── #59 part 2: run swtpm WITHOUT -d ────────────────────────────────────────
# Final discriminator, both inside the SAME failing container and with the same
# state path:
#   dockur's form   swtpm socket -t -d … --pid file=…   -> no socket, no pid file
#   backgrounded    swtpm socket -t    … (no -d)        -> socket bound instantly
# So the blocker is the -d daemonization, not the state path and not any of the
# five earlier theories. dockur cannot see this because -d makes the parent exit
# 0 regardless of what the child does.
#
# boot.sh only copies /usr/bin/swtpm to $SWTPM when $SWTPM is not already
# executable, so shipping an executable wrapper at that path takes over the
# invocation without touching boot.sh further. The wrapper drops -d, runs swtpm
# under setsid in the background, writes the pid file dockur polls for, and
# waits for the control socket to appear.
echo "+ installing swtpm wrapper that drops -d (#59)"
SWTPM_WRAP=$(mktemp)
cat << 'EOF' > "$SWTPM_WRAP"
#!/bin/sh
# wootc (#59): dockur launches swtpm with -d; in this container the daemonized
# child never binds its control socket nor writes its pid file, and -d hides the
# failure. Run it in the background instead and wait for the socket.
PIDFILE=""; SOCK=""; NEWARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) ;;                                   # drop daemonize
    --pid)  PIDFILE=$(printf '%s' "$2" | sed 's/^file=//')
            NEWARGS="$NEWARGS --pid $2"; shift ;;
    --ctrl) SOCK=$(printf '%s' "$2" | sed 's/.*path=//')
            NEWARGS="$NEWARGS --ctrl $2"; shift ;;
    *) NEWARGS="$NEWARGS $1" ;;
  esac
  shift
done
# shellcheck disable=SC2086  # word splitting is intended
setsid /usr/bin/swtpm $NEWARGS >/tmp/wootc-swtpm.log 2>&1 &
child=$!
[ -n "$PIDFILE" ] && printf '%s\n' "$child" > "$PIDFILE" 2>/dev/null
i=0
while [ "$i" -lt 60 ]; do
  [ -n "$SOCK" ] && [ -S "$SOCK" ] && exit 0
  kill -0 "$child" 2>/dev/null || break
  i=$((i + 1)); sleep 0.2
done
exit 0
EOF
podman cp "$SWTPM_WRAP" "$BUILDER:/run/swtpm"
rm -f "$SWTPM_WRAP"
podman exec "$BUILDER" chmod +x /run/swtpm

echo "+ installing authorized_keys (key-only auth)"
podman exec "$BUILDER" mkdir -p /root/.ssh
podman cp "${KEYFILE}.pub" "$BUILDER:/root/.ssh/authorized_keys"
podman exec "$BUILDER" sh -c "chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"
podman exec "$BUILDER" sh -c \
    "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/;s/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"

echo "+ installing entrypoint wrapper (sshd, then chain to the original entrypoint unmodified)"
WRAPPER=$(mktemp)
cat << 'EOF' > "$WRAPPER"
#!/bin/sh
mkdir -p /run/sshd
/usr/sbin/sshd

while true; do
  rm -f /run/shm/qemu.end /run/shm/qemu.pid /run/shm/qemu.pty /run/shm/console.pid /run/shm/console.sock
  /usr/bin/tini -s /run/entry.sh || true
  echo "[wootc-entrypoint] QEMU exited; restarting in 2 seconds..."
  sleep 2
done
EOF
podman cp "$WRAPPER" "$BUILDER:/usr/local/bin/wootc-entrypoint.sh"
rm -f "$WRAPPER"
podman exec "$BUILDER" chmod +x /usr/local/bin/wootc-entrypoint.sh

echo "+ committing $TARGET_IMAGE"
podman commit \
    --change 'ENTRYPOINT ["/usr/local/bin/wootc-entrypoint.sh"]' \
    --change 'CMD []' \
    "$BUILDER" "$TARGET_IMAGE"
podman rm -f "$BUILDER" >/dev/null

echo "+ done: $TARGET_IMAGE"
podman images "$TARGET_IMAGE"
echo
echo "Connect once the container is running (add \"2222:22\" to compose.yml's ports:):"
echo "  ssh -i $KEYFILE -p 2222 root@localhost"
