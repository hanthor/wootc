#!/usr/bin/env bats
# steps-catalogue.bats — single source of truth step catalogue contract (issue #334)
# Asserts that payload/steps.tsv is valid, deploy.sh phase calls match the catalogue,
# every deployer step has a splash entry, and generated files are not stale.

TSV="payload/steps.tsv"
DEPLOY="payload/deployer/deploy.sh"
STEPS_SH="tests/e2e/steps.sh"
STEPS_GO="app/steps_gen.go"
GEN="payload/gen-steps.py"

@test "payload/steps.tsv exists and is well-formed" {
    [ -f "$TSV" ]
    # Must have at least 15 steps
    count=$(grep -v '^[[:space:]]*#' "$TSV" | grep -v '^[[:space:]]*$' | wc -l)
    [ "$count" -ge 15 ]

    # Verify each line has 3 tab-separated fields and a valid owner
    while IFS=$'\t' read -r step_id owner label || [ -n "$step_id" ]; do
        [[ "$step_id" =~ ^[[:space:]]*# ]] && continue
        [ -z "$step_id" ] && continue
        [ -n "$owner" ]
        [ -n "$label" ]
        [[ "$owner" =~ ^(installer|deployer|firstboot)$ ]]
    done < "$TSV"
}

@test "every phase \"x\" call in deploy.sh is catalogued with owner deployer" {
    # Extract every `phase "foo"` call from deploy.sh
    phases=$(grep -oE 'phase "[a-zA-Z0-9_-]+"' "$DEPLOY" | sed -E 's/phase "([^"]+)"/\1/' | sort -u)
    [ -n "$phases" ]

    for p in $phases; do
        # Must exist in steps.tsv with owner deployer
        grep -qE "^${p}[[:space:]]+deployer[[:space:]]+" "$TSV"
    done
}

@test "every deployer step in payload/steps.tsv has a splash line in deploy.sh" {
    while IFS=$'\t' read -r step_id owner label || [ -n "$step_id" ]; do
        [[ "$step_id" =~ ^[[:space:]]*# ]] && continue
        [ -z "$step_id" ] && continue
        if [ "$owner" = "deployer" ]; then
            grep -qE "^[[:space:]]*${step_id}\)[[:space:]]+splash_set" "$DEPLOY"
        fi
    done < "$TSV"
}

@test "generated files are not stale (python3 payload/gen-steps.py --check)" {
    python3 "$GEN" --check
}

@test "tests/e2e/steps.sh defines valid arrays and is_valid_phase" {
    [ -f "$STEPS_SH" ]
    source "$STEPS_SH"
    [ "${#DEPLOYER_PHASES[@]}" -gt 0 ]
    [ "${#INSTALLER_STEPS[@]}" -gt 0 ]
    [ "${#FIRSTBOOT_STEPS[@]}" -gt 0 ]
    [ "${#ALL_PHASES[@]}" -gt 0 ]

    # Test is_valid_phase
    is_valid_phase "fisherman"
    is_valid_phase "check-pc"
    is_valid_phase "firstboot-evidence"

    run is_valid_phase "unknown-phase-name"
    [ "$status" -ne 0 ]
}
