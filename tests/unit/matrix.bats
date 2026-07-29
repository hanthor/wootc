#!/usr/bin/env bats
# matrix.bats — the E2E matrix must actually cover the axes it claims, and the
# runner must actually deliver per-case knobs to the runs.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MATRIX="$REPO_ROOT/tests/e2e/matrix.tsv"
    RUNNER="$REPO_ROOT/tests/e2e/run-matrix.sh"
}

@test "matrix covers Windows 10 and 11, Home and Pro" {
    awk -F'\t' '!/^#/ && $4=="11" && $5=="pro"'  "$MATRIX" | grep -q .
    awk -F'\t' '!/^#/ && $4=="10" && $5=="pro"'  "$MATRIX" | grep -q .
    awk -F'\t' '!/^#/ && $4=="11" && $5=="home"' "$MATRIX" | grep -q .
    awk -F'\t' '!/^#/ && $4=="10" && $5=="home"' "$MATRIX" | grep -q .
}

@test "Home generic keys match their Windows major version" {
    # Win11's YTMG3 key is not accepted by the Win10 consumer ISO. Setup then
    # presents "No images are available" and waits forever for input (hosted
    # run 30427966283). Keep the edition axis grounded in the ISO it selects.
    awk -F'\t' '
        !/^#/ && $4=="11" && $5=="home" { found=1; if ($6!="YTMG3-N6DKC-DKB77-7M9GH-8HVX7") exit 1 }
        END { if (!found) exit 1 }
    ' "$MATRIX"
    awk -F'\t' '
        !/^#/ && $4=="10" && $5=="home" { found=1; if ($6!="TX9XD-98N7V-6WMQ6-BX7FG-H8Q99") exit 1 }
        END { if (!found) exit 1 }
    ' "$MATRIX"
}

@test "matrix covers the BitLocker axis including Home device-encryption" {
    grep -v '^#' "$MATRIX" | grep 'bitlocker=on' | grep -q $'\thome\t'
    grep -v '^#' "$MATRIX" | grep 'bitlocker=on' | grep -q $'\tpro\t'
}

@test "matrix covers all three deployment backends" {
    # ostree backend (incl. sealed-rootfs bluefin), composefs-native (dakota).
    # Measured contract: docs/backend-contract.md
    grep -v '^#' "$MATRIX" | grep -q 'tuna-os/yellowfin'
    grep -v '^#' "$MATRIX" | grep -q 'projectbluefin/bluefin:lts'
    grep -v '^#' "$MATRIX" | grep -q 'projectbluefin/dakota'
}

@test "matrix has a phase3 case per backend flavor" {
    grep -v '^#' "$MATRIX" | grep 'phase3=on' | grep -q 'yellowfin'
    grep -v '^#' "$MATRIX" | grep 'phase3=on' | grep -q 'bluefin:lts'
    grep -v '^#' "$MATRIX" | grep 'phase3=on' | grep -q 'dakota'
}

@test "host_worker threads the opts column through to run_case" {
    # It previously read five fields and passed a stale $opts global from the
    # planning loop — bitlocker=on silently never reached any run.
    grep -q 'while IFS=\$'"'"'\\t'"'"' read -r name image ver ed key opts; do' "$RUNNER"
    # Signature gained "$inst"/"$vm_ram" when per-host slots and RAM budgeting
    # landed; what this guards is that $opts still reaches run_case as the LAST
    # argument, read fresh from the queue rather than inherited from planning.
    grep -q 'run_case "\$host" "\$inst" "\$vm_ram" "\$name" "\$image" "\$ver" "\$ed" "\$key" "\$opts"' "$RUNNER"
}

@test "phase3=on translates to --phase3 on the remote invocation" {
    grep -q 'phase3=on\*) EXTRA_ARGS="--phase3"' "$RUNNER"
    # --instance= joined the invocation with per-host slots; EXTRA_ARGS must
    # still be expanded ON THE REMOTE (escaped \$) and not by the local shell.
    grep -q 'run-e2e.sh "\$image" --keep --instance=\$inst \\\$EXTRA_ARGS' "$RUNNER"
}

@test "himachal has a hard ceiling of one concurrent VM" {
    # Two VMs drove himachal (18 cores, 15 GiB) to load average 100 and then to
    # a full freeze needing a power cycle (2026-07-27). The ceiling must beat
    # BOTH size_host's arithmetic and an explicit --jobs, because the failure
    # mode is a dead machine rather than a slow run.
    grep -q 'himachal) echo 1 ;;' "$RUNNER"
    # Applied after --jobs is honoured, so it cannot be overridden from the CLI.
    jobs_line=$(grep -n '\[ "\$JOBS" != auto \] && n="\$JOBS"' "$RUNNER" | cut -d: -f1)
    cap_line=$(grep -n 'host_cap=\$(host_max_jobs "\$host")' "$RUNNER" | cut -d: -f1)
    [ -n "$jobs_line" ]
    [ -n "$cap_line" ]
    [ "$cap_line" -gt "$jobs_line" ]
}

@test "a case waits for a loaded host instead of piling onto it" {
    # himachal reached load average 100 and then froze hard enough to need a
    # power cycle (2026-07-27), costing the phase3 axis a whole cycle. A busy
    # host is a reason to WAIT, not to add another Windows VM to it.
    grep -q '/proc/loadavg' "$RUNNER"
    grep -q 'waiting before launching' "$RUNNER"
    # The wait must happen BEFORE the launch attempts.
    wait_line=$(grep -n 'load .* on .* cores — waiting before launching' "$RUNNER" | head -1 | cut -d: -f1)
    launch_line=$(grep -n 'for attempt in 1 2 3; do' "$RUNNER" | head -1 | cut -d: -f1)
    [ -n "$wait_line" ]
    [ -n "$launch_line" ]
    [ "$wait_line" -lt "$launch_line" ]
}

@test "the matrix runs from an immutable snapshot of itself" {
    # bash reads a script lazily by byte offset, so editing run-matrix.sh while
    # a sweep is running corrupts THAT sweep. A phase3 sweep died with
    # "line 310: syntax error near unexpected token `and`" for exactly this
    # reason on 2026-07-27 — a result that looked like a test failure.
    grep -q 'WOOTC_MATRIX_SNAPSHOT' "$RUNNER"
    grep -q 'exec bash "\$_snap"' "$RUNNER"
    # $0 becomes the snapshot, so HERE must come from the recorded origin.
    grep -q 'HERE="\${WOOTC_MATRIX_HOME:-' "$RUNNER"
    # The re-exec must precede any use of HERE.
    snap_line=$(grep -n 'exec bash "\$_snap"' "$RUNNER" | head -1 | cut -d: -f1)
    here_line=$(grep -n '^HERE=' "$RUNNER" | head -1 | cut -d: -f1)
    [ "$snap_line" -lt "$here_line" ]
}

@test "--grep is a regex so an iteration loop can name distinct code paths" {
    # 23 cells collapse to five distinct paths: ostree baseline, win10,
    # composefs, BitLocker, bonito bridge. The other 18 are ISO-edition, desktop
    # and phase3 permutations of those — fanning out while most cells are red
    # costs 4x the runner time for the same two or three causes. A substring
    # match cannot express "these five".
    grep -q '\$2 ~ want' "$RUNNER"
    run grep -c 'index(\$2, want)' "$RUNNER"
    [ "$output" -eq 0 ]
}
