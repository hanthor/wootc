#!/usr/bin/env bash
# packaging/brands.sh — which brands may be built into a release, and why.
#
# Branded distribution is a claim on somebody else's mark. `app/branding/*/`
# holds the marks; `app/branding/*/blessing.json` holds the DECISION about
# each one (#227), and this script is the thing that makes that decision
# load-bearing instead of documentary:
#
#   blessed   the project said yes — build it
#   pending   nobody has said no, and shipping predates the ask — build it,
#             but say out loud in the log that it is unblessed
#   declined  the project said no — the exe drops from the release matrix
#
# A brand with NO record at all is a hard error, not a default-yes. That is
# the whole point: a new app/branding/<x>/ directory cannot reach a release
# without someone writing down who was asked and what they said.
#
# Usage:
#   brands.sh list      one "<brand><TAB><exeName>" per BUILDABLE brand
#   brands.sh explain   the full table, every brand, with its reason
#
# Env:
#   WOOTC_BRANDING_DIR      override the branding root (tests)
#   WOOTC_REQUIRE_BLESSING  1 = ship blessed brands ONLY; pending drops too.
#                           The knob exists so tightening the policy is a
#                           workflow setting, not another code change.
set -euo pipefail

BRANDING_DIR="${WOOTC_BRANDING_DIR:-app/branding}"
REQUIRE_BLESSING="${WOOTC_REQUIRE_BLESSING:-0}"

die() { echo "brands.sh: $*" >&2; exit 1; }

command -v jq >/dev/null || die "jq is required"
[ -d "$BRANDING_DIR" ] || die "no branding directory at $BRANDING_DIR"

# Echoes "<status>|<exeName>|<reason>" for one brand directory, or exits
# non-zero with the reason on stderr when the record is unusable. Validation
# lives here rather than only in the Go test so a release cannot be cut from a
# tree whose records do not parse.
inspect() {
    local dir="$1" brand exe status bless
    brand=$(basename "$dir")
    bless="$dir/blessing.json"

    [ -f "$dir/brand.json" ] || die "$brand: no brand.json"
    exe=$(jq -r '.exeName // empty' "$dir/brand.json") \
        || die "$brand: unparseable brand.json"
    [ -n "$exe" ] || die "$brand: brand.json has no exeName"

    [ -f "$bless" ] || die "$brand: no blessing.json — a brand ships only with a recorded decision (#227); see docs/upstream-blessings.md"
    status=$(jq -r '.status // empty' "$bless") \
        || die "$brand: unparseable blessing.json"

    case "$status" in
        blessed)
            printf '%s|%s|%s\n' build "$exe" "blessed by $(jq -r '.mark.owner // "?"' "$bless")"
            ;;
        pending)
            if [ "$REQUIRE_BLESSING" = "1" ]; then
                printf '%s|%s|%s\n' skip "$exe" "blessing still pending and WOOTC_REQUIRE_BLESSING=1"
            else
                printf '%s|%s|%s\n' warn "$exe" "UNBLESSED — the ask to $(jq -r '.mark.owner // "?"' "$bless") is not answered yet"
            fi
            ;;
        declined)
            printf '%s|%s|%s\n' declined "$exe" "$(jq -r '.mark.owner // "the project"' "$bless") declined — this exe is not ours to ship"
            ;;
        *)
            die "$brand: blessing.json status is '${status}', not blessed/pending/declined"
            ;;
    esac
}

brand_dirs() {
    local dir
    for dir in "$BRANDING_DIR"/*/; do
        [ -d "$dir" ] || continue
        printf '%s\n' "${dir%/}"
    done
}

cmd_list() {
    local dir brand line verdict exe
    while read -r dir; do
        brand=$(basename "$dir")
        # Assign, THEN split. `read ... < <(inspect)` would run inspect in a
        # subshell whose die() cannot stop this one, so an unusable record
        # would be silently skipped — the default-yes this exists to refuse.
        line=$(inspect "$dir")
        IFS='|' read -r verdict exe _ <<<"$line"
        case "$verdict" in
            build|warn) printf '%s\t%s\n' "$brand" "$exe" ;;
        esac
    done < <(brand_dirs)
}

cmd_explain() {
    local dir brand line verdict exe reason unblessed=0
    echo "Brand release matrix (app/branding/*/blessing.json — #227)"
    while read -r dir; do
        brand=$(basename "$dir")
        line=$(inspect "$dir")
        IFS='|' read -r verdict exe reason <<<"$line"
        case "$verdict" in
            build)
                printf '  BUILD    %-20s %s.exe — %s\n' "$brand" "$exe" "$reason" ;;
            warn)
                unblessed=$((unblessed + 1))
                printf '  BUILD*   %-20s %s.exe — %s\n' "$brand" "$exe" "$reason" ;;
            skip)
                printf '  SKIP     %-20s %s.exe — %s\n' "$brand" "$exe" "$reason" ;;
            declined)
                printf '  DROPPED  %-20s %s.exe — %s\n' "$brand" "$exe" "$reason" ;;
        esac
    done < <(brand_dirs)
    if [ "$unblessed" -gt 0 ]; then
        echo "  * $unblessed brand(s) ship on a PENDING record. Chase the ask:"
        echo "    docs/upstream-blessings.md"
    fi
}

case "${1:-}" in
    list)    cmd_list ;;
    explain) cmd_explain ;;
    *)       die "usage: brands.sh {list|explain}" ;;
esac
