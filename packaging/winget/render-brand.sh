#!/usr/bin/env bash
# render-brand.sh — the winget manifests for a BRANDED installer, rendered so
# they can be handed to the project whose namespace they would live in (#227).
#
# `Bazzite.Installer` sits in Bazzite's publisher namespace, not ours. The
# useful form of "may we?" is not a description of a package — it is the
# package, rendered, so they can read exactly what would be published under
# their name and either take it over or say no.
#
# This renders; it never submits. Only TunaOS.wootc is submitted automatically
# (.github/workflows/winget-publish.yml), and no branded package is submitted
# anywhere without `winget.identifierAgreed` in that brand's blessing.json.
#
# Usage:
#   render-brand.sh <brand> [version] [url] [sha256]
#
# With no version/url/sha the placeholders stay in place, which is enough to
# show the shape of the package before a release exists.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATES="$ROOT/packaging/winget/brand"

die() { echo "render-brand.sh: $*" >&2; exit 1; }

brand="${1:-}"
[ -n "$brand" ] || die "usage: render-brand.sh <brand> [version] [url] [sha256]"
# Unset arguments stay as placeholders: the manifests are worth showing to a
# project before any release of that brand exists.
version="${2:-}"; tag="v$version"
if [ -z "$version" ]; then version='{{VERSION}}'; tag='{{TAG}}'; fi
url="${3:-}";     [ -n "$url" ] || url='{{URL}}'
sha="${4:-}";     [ -n "$sha" ] || sha='{{SHA256}}'

command -v jq >/dev/null || die "jq is required"
dir="$ROOT/app/branding/$brand"
[ -d "$dir" ] || die "no such brand: $brand"

bless="$dir/blessing.json"
[ -f "$bless" ] || die "$brand has no blessing.json (#227) — nothing to offer until someone is being asked"

identifier=$(jq -r '.winget.identifier // empty' "$bless")
owner=$(jq -r '.winget.namespaceOwner // empty' "$bless")
status=$(jq -r '.status // empty' "$bless")
agreed=$(jq -r '.winget.identifierAgreed // false' "$bless")
[ -n "$identifier" ] || die "$brand: blessing.json names no winget.identifier"

name=$(jq -r '.name // empty' "$dir/brand.json")
product=$(jq -r '.productName // empty' "$dir/brand.json")
tagline=$(jq -r '.tagline // empty' "$dir/brand.json")
exe=$(jq -r '.exeName // empty' "$dir/brand.json")
[ -n "$name" ] && [ -n "$product" ] && [ -n "$tagline" ] && [ -n "$exe" ] \
    || die "$brand: brand.json is missing name/productName/tagline/exeName"

publisher="${identifier%%.*}"
moniker=$(printf '%s' "$identifier" | tr '[:upper:]' '[:lower:]' | tr '.' '-')

# The publisher URL is the BRAND's home, not ours — the package is published
# in their namespace. Fall back to this repo only for our own marks, whose
# assetSource is an emoji rather than a site.
publisher_url=$(jq -r '.mark.assetSource // empty' "$bless")
case "$publisher_url" in
    http*) ;;
    *) publisher_url="https://github.com/tuna-os/wootc" ;;
esac

# Never let a rendered artifact assert a permission nobody has given.
if [ "$agreed" = "true" ]; then
    permission="The $name name and mark are used with the $name project's permission."
else
    permission="PERMISSION NOT YET GRANTED — this is a draft offered for review, not a submission."
fi

# The header is addressed to a human deciding whether to accept this, so it
# says who owns the namespace and what has actually been agreed — never let a
# rendered artifact imply a permission that has not been given.
cat <<HEADER
# winget manifests for $product ($identifier)
#
# Namespace owner : $owner
# Blessing status : $status (identifier agreed: $agreed)
# Rendered by     : packaging/winget/render-brand.sh — NOT submitted anywhere.
#
# $identifier is $owner's to publish. These are offered so that decision can
# be made against the real thing; take them over, ask us to publish on your
# behalf, or say no and nothing is submitted.
HEADER

for template in "$TEMPLATES"/version.yaml.in \
                "$TEMPLATES"/installer.yaml.in \
                "$TEMPLATES"/locale.en-US.yaml.in; do
    [ -f "$template" ] || die "missing template $template"
    out="$identifier.$(basename "${template%.yaml.in}").yaml"
    printf '\n--- %s ---\n' "$out"
    sed -e "s|{{IDENTIFIER}}|$identifier|g" \
        -e "s|{{VERSION}}|$version|g" \
        -e "s|{{TAG}}|$tag|g" \
        -e "s|{{URL}}|$url|g" \
        -e "s|{{SHA256}}|$sha|g" \
        -e "s|{{PUBLISHER}}|$publisher|g" \
        -e "s|{{PUBLISHER_URL}}|$publisher_url|g" \
        -e "s|{{PACKAGE_NAME}}|$product|g" \
        -e "s|{{BRAND_NAME}}|$name|g" \
        -e "s|{{TAGLINE}}|$tagline|g" \
        -e "s|{{COMMAND}}|$exe|g" \
        -e "s|{{MONIKER}}|$moniker|g" \
        -e "s|{{PERMISSION}}|$permission|g" \
        "$template"
done
