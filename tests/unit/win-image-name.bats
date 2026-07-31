#!/usr/bin/env bats
# win-image-name.bats — choosing the ISO's own WIM image name (#58).
#
# Windows Setup pauses on the edition picker when the answer file's key matches
# several images in the ISO, or none. The documented fix is /IMAGE/NAME — but a
# name Setup cannot resolve stalls on that very picker, so a WRONG name is
# strictly worse than no name at all (run 20260727T101713Z died exactly that
# way after a guessed "Windows 10 Pro").
#
# Hence: never guess from a table, read the media, and when the answer is
# ambiguous send nothing and let Setup decide. These tests pin that contract
# against real image-name lists as the ISOs actually spell them.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    # Source just the function under test; run-e2e.sh is not sourceable whole.
    eval "$(sed -n '/^pick_win_image_name() {$/,/^}$/p' "$REPO_ROOT/tests/e2e/run-e2e.sh")"
    # `run bash -c` spawns a child shell, which cannot see a function defined
    # only in this one.
    export -f pick_win_image_name
}

@test "picks Pro without matching Pro N or Pro Education" {
    run bash -c 'printf "%s\n" "Windows 11 Home" "Windows 11 Home N" "Windows 11 Pro" "Windows 11 Pro N" "Windows 11 Pro Education" | pick_win_image_name pro'
    [ "$status" -eq 0 ]
    [ "$output" = "Windows 11 Pro" ]
}

@test "picks LTSC, which spells itself Enterprise LTSC" {
    run bash -c 'printf "%s\n" "Windows 11 Enterprise LTSC 2024" | pick_win_image_name ltsc'
    [ "$output" = "Windows 11 Enterprise LTSC 2024" ]
}

@test "plain Enterprise never resolves to the LTSC image" {
    # An ISO carrying only LTSC must NOT hand back an LTSC name for a plain
    # Enterprise request: Setup would fail to match the key and stall.
    run bash -c 'printf "%s\n" "Windows 11 Enterprise LTSC 2024" | pick_win_image_name enterprise'
    [ -z "$output" ]
}

@test "an ambiguous list yields nothing rather than a coin flip" {
    # Two plausible matches is the case this function exists to refuse: a name
    # matching two images is no better than a wrong one.
    run bash -c 'printf "%s\n" "Windows 10 Pro" "Windows 10 Pro for Workstations" "Windows 10 Pro Anniversary" | pick_win_image_name pro'
    [ -z "$output" ]
}

@test "no match yields nothing, leaving Setup to decide" {
    run bash -c 'printf "%s\n" "Windows 11 Home" | pick_win_image_name enterprise'
    [ -z "$output" ]
}

@test "an unknown edition never guesses" {
    run bash -c 'printf "%s\n" "Windows 11 Pro" | pick_win_image_name banana'
    [ -z "$output" ]
}

@test "surrounding whitespace in wiminfo output is tolerated" {
    run bash -c 'printf "%s\n" "  Windows 11 Pro  " | pick_win_image_name pro'
    [ "$output" = "Windows 11 Pro" ]
}

@test "the in-run heal only fires when it can add information" {
    # It must never touch a case that already works: no-op when the image name
    # was resolved before boot, and no-op on the snapshot restore path (which
    # never runs Windows Setup at all). Both guards live at the top of the
    # function, so assert them at the source rather than booting a VM.
    local f="$REPO_ROOT/tests/e2e/run-e2e.sh"
    run bash -c "sed -n '/^heal_image_name_from_downloaded_iso() {/,/^}/p' '$f'"
    [ -n "$output" ]
    echo "$output" | grep -q '\[ -z "\$WIN_IMAGE_NAME" \] || return 0'
    echo "$output" | grep -q '\[ "\$SKIP_INSTALL" = true \] && return 0'
}

@test "the in-run heal waits for the download to settle before reading" {
    # Reading a still-downloading ISO would derive a name from a truncated
    # file — a wrong name is worse than none (#58), so it must compare sizes.
    local f="$REPO_ROOT/tests/e2e/run-e2e.sh"
    run bash -c "sed -n '/^heal_image_name_from_downloaded_iso() {/,/^}/p' '$f'"
    echo "$output" | grep -q 'eq "\$prev"'
}

@test "the in-run heal never proceeds on an ambiguous list" {
    local f="$REPO_ROOT/tests/e2e/run-e2e.sh"
    run bash -c "sed -n '/^heal_image_name_from_downloaded_iso() {/,/^}/p' '$f'"
    echo "$output" | grep -q 'if \[ -z "\$derived" \]'
}
