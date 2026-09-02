#!/usr/bin/env bats
# soak-ledger.bats — green-nightly soak ledger and 1.0 gate instrumentation (M4.7 / #235).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    DOC="$REPO_ROOT/docs/soak.md"
    WORKFLOW="$REPO_ROOT/.github/workflows/soak-ledger.yml"
    TOOL="$REPO_ROOT/tools/soak-ledger/soak_ledger.py"
    PAGES="$REPO_ROOT/pages/soak/index.html"
    PAGES_JSON="$REPO_ROOT/pages/soak/ledger.json"
}

@test "docs/soak.md exists and carries the 1.0 gate structure" {
    [ -f "$DOC" ]
    grep -q "# Green-Nightly Soak Ledger (1.0 Gate)" "$DOC"
    grep -q "Live Gate Status" "$DOC"
    grep -q "Current Live Streak" "$DOC"
    grep -q "1.0 Soak Streak" "$DOC"
    grep -q "Soak Start Date" "$DOC"
    grep -q "Policy & Operating Rules" "$DOC"
    grep -q "Ledger Table" "$DOC"
}

@test "docs/soak.md table contains required columns" {
    grep -q "Date (UTC)" "$DOC"
    grep -q "Commit SHA" "$DOC"
    grep -q "Workflow Run" "$DOC"
    grep -q "Image" "$DOC"
    grep -q "Verdict" "$DOC"
    grep -q "Auto-Release" "$DOC"
    grep -q "Diagnosis / Issue" "$DOC"
}

@test "soak_ledger.py tool is executable and passes self-check" {
    [ -x "$TOOL" ]
    run python3 "$TOOL" --help
    [ "$status" -eq 0 ]
    grep -q "update" <<< "$output"
    grep -q "check" <<< "$output"
    grep -q "summary" <<< "$output"
}

@test "soak_ledger.py check passes on the committed ledger" {
    run python3 "$TOOL" check --doc "$DOC"
    [ "$status" -eq 0 ]
    grep -q "Integrity status: VALID" <<< "$output"
}

@test "soak_ledger.py summary outputs live status line" {
    run python3 "$TOOL" summary --doc "$DOC"
    [ "$status" -eq 0 ]
    grep -q "Soak streak:" <<< "$output"
    grep -q "1.0 Gate:" <<< "$output"
}

@test "soak-ledger.yml workflow is wired to E2E GUI nightly completion and schedule" {
    [ -f "$WORKFLOW" ]
    grep -q "workflow_run" "$WORKFLOW"
    grep -q "E2E GUI-driven (publish timelapse)" "$WORKFLOW"
    grep -q "schedule:" "$WORKFLOW"
    grep -q "contents: write" "$WORKFLOW"
    grep -q "soak_ledger.py update" "$WORKFLOW"
}

@test "pages/soak dashboard assets exist" {
    [ -f "$PAGES" ]
    [ -f "$PAGES_JSON" ]
    grep -q "Green-Nightly Soak Ledger" "$PAGES"
}

@test "ROADMAP and status docs cite the soak ledger" {
    grep -q "docs/soak.md" "$REPO_ROOT/ROADMAP.md"
    grep -q "soak.md" "$REPO_ROOT/docs/status.md"
    grep -q "soak.md" "$REPO_ROOT/docs/RELEASING.md"
}
