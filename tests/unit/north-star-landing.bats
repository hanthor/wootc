#!/usr/bin/env bats
# North Star landing contracts: what greets the user on their new desktop.
# The audit of 2026-08-22 found the first login silent — no welcome, no
# pointer at the migration tools, and everything outside the six bridged
# folders reachable only by typing /run/wootc/host.

DEPLOY="payload/deployer/deploy.sh"
MOUNTDIRS="payload/migration/wootc-mount-user-dirs"
WELCOME="payload/migration/wootc-welcome"

@test "a first-login welcome exists, is visible, and runs once" {
    [ -f "$WELCOME" ]
    [ -f payload/migration/wootc-welcome.desktop ]
    # Visible, unlike apply-look (which is deliberately NoDisplay).
    run grep 'NoDisplay=true' payload/migration/wootc-welcome.desktop
    [ "$status" -ne 0 ]
    # One-shot: a marker file silences every later login.
    grep -q 'welcomed' "$WELCOME"
    grep -q 'exit 0' "$WELCOME"
}

@test "the welcome opens the migration dashboard, with a fallback that still says hello" {
    grep -q 'wootc-manifest-gui' "$WELCOME"
    grep -q 'notify-send' "$WELCOME"
}

@test "the deployer stages the welcome as an autostart" {
    grep -q 'wootc-welcome.desktop' "$DEPLOY"
    grep -q 'etc/xdg/autostart/wootc-welcome.desktop' "$DEPLOY"
}

@test "every bridged home gets a Windows-drive bookmark" {
    # bind_profile is the single shared bridge path (exact-name and
    # single-user fallback), so hooking the bookmark there covers both.
    grep -q 'add_host_bookmark "$home"' "$MOUNTDIRS"
    grep -q 'file:///run/wootc/host Windows drive' "$MOUNTDIRS"
    # Never duplicated across logins, and owned by the user (the unit runs
    # as root — a root-owned ~/.config/gtk-3.0 breaks the file manager).
    grep -q 'grep -qsF' "$MOUNTDIRS"
    grep -q -- '--reference="$home"' "$MOUNTDIRS"
    # Both GTK generations read their own path.
    grep -q 'gtk-3.0 gtk-4.0' "$MOUNTDIRS"
}
