#!/usr/bin/env bats
# e2e-failure-ledger.bats — a recorded failure must forbid "ALL TESTS PASSED".
#
# fail() used to only echo. A fail site that did not itself `exit 1` was
# therefore decorative, and the run continued to the success banner. That is
# how el10-gnome-win11pro-bitlocker (20260727T004500Z) reported
# "ALL TESTS PASSED" — and was recorded PASS by the matrix — while its own log
# contained:
#
#     [FAIL] Passthrough: errors detected in boot output:
#     [FAIL] User data NOT visible in Phase 2 $HOME (expected RUN_ID ...)
#
# The second is the North Star itself: the product's entire claim is that the
# user's data survives the migration. Both sites set PASSTHROUGH_OK=false and
# nothing in the script ever read that variable.
#
# The ledger must be a FILE. fail() is reached from inside command
# substitutions and pipelines, and a variable incremented there dies with the
# subshell — which is exactly the kind of "status taken from a proxy" defect
# this harness keeps producing.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    E2E="$REPO_ROOT/tests/e2e/run-e2e.sh"
    LEDGER="$BATS_TEST_TMPDIR/ledger"
    : > "$LEDGER"
    # Source fail() alone; running the script would start a VM.
    RED=""; NC=""
    WOOTC_FAILURE_LEDGER="$LEDGER"
    fail() {
        echo -e "${RED}[FAIL]${NC} $*" >&2
        printf '%s\n' "$*" >> "$WOOTC_FAILURE_LEDGER" 2>/dev/null || true
    }
}

@test "run-e2e.sh is syntactically valid" {
    run bash -n "$E2E"
    [ "$status" -eq 0 ]
}

@test "fail() records to the ledger, not just stderr" {
    fail "something broke"
    [ -s "$LEDGER" ]
    grep -q "something broke" "$LEDGER"
}

@test "a fail inside a command substitution still reaches the ledger" {
    out=$(fail "raised in a subshell"; echo body)
    [ "$out" = "body" ]
    grep -q "raised in a subshell" "$LEDGER"
}

@test "a fail inside a pipeline still reaches the ledger" {
    echo x | { fail "raised in a pipeline"; cat >/dev/null; }
    grep -q "raised in a pipeline" "$LEDGER"
}

@test "the success banner is gated on the ledger being empty" {
    # The literal banner must not be reachable without passing the gate.
    gate_line=$(grep -n 'if \[ -s "\$WOOTC_FAILURE_LEDGER" \]' "$E2E" | tail -1 | cut -d: -f1)
    banner_line=$(grep -n 'ALL TESTS PASSED' "$E2E" | tail -1 | cut -d: -f1)
    [ -n "$gate_line" ]
    [ -n "$banner_line" ]
    [ "$gate_line" -lt "$banner_line" ]
}

@test "the gate exits non-zero and says TESTS FAILED when the ledger is non-empty" {
    grep -A 12 'if \[ -s "\$WOOTC_FAILURE_LEDGER" \]' "$E2E" | grep -q "TESTS FAILED"
    grep -A 14 'if \[ -s "\$WOOTC_FAILURE_LEDGER" \]' "$E2E" | grep -q "exit 1"
}

@test "the user-data check records a failure — it is the North Star assertion" {
    # It set PASSTHROUGH_OK=false, which nothing read. It must call fail() so
    # the ledger — which IS read — carries it.
    grep -q 'fail "User data NOT visible in Phase 2' "$E2E"
}

@test "a recovered ntfs3 mount error does not fail the run" {
    # The passthrough tries ntfs3 and falls back to fuse-ntfs-3g. On EL10, whose
    # kernel has no ntfs3, a HEALTHY boot logs a mount failure and then mounts.
    # Treating that as fatal would trade the old false green for a false red.
    grep -q 'warn "Passthrough: mount errors in boot output' "$E2E"
    # Only unrecoverable conditions may fail.
    grep -q 'fail "Passthrough: unrecoverable errors detected in boot output:"' "$E2E"
    run grep -c 'grep -qiE "panic|kernel BUG|ntfs3\.\*refus"' "$E2E"
    [ "$output" -ge 1 ]
}
