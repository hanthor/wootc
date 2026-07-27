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
