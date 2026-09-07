#!/bin/zsh
# Update a Homebrew-tap checkout's Casks/lookaround.rb to a new version.
#
# Usage (from a clone of your tap repo, e.g. henryle97/homebrew-tap):
#   /path/to/look-around/scripts/bump-cask.sh 1.0.0 <sha256>
#   /path/to/look-around/scripts/bump-cask.sh 1.0.0   # reads
#     look-around/dist/LookAround-1.0.0.dmg.sha256 if present
#
# Run from anywhere inside the tap repo (Casks/lookaround.rb must exist).
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: bump-cask.sh <version> [sha256]" >&2
    exit 1
fi
VERSION="${1#v}"
SHA="${2:-}"

if [[ -z "$SHA" ]]; then
    # Locate the look-around checkout relative to this script.
    APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    SIDECAR="$APP_ROOT/dist/LookAround-${VERSION}.dmg.sha256"
    if [[ ! -f "$SIDECAR" ]]; then
        echo "✗ no sha given and $SIDECAR not found" >&2
        exit 1
    fi
    SHA=$(awk '{print $1}' "$SIDECAR")
fi

CASK="Casks/lookaround.rb"
if [[ ! -f "$CASK" ]]; then
    echo "✗ $CASK not found — run from your homebrew-tap checkout" >&2
    exit 1
fi

sed -i '' -e "s/^  version .*/  version \"${VERSION}\"/" \
           -e "s/^  sha256 .*/  sha256 \"${SHA}\"/" "$CASK"

echo "✓ $CASK → version $VERSION"
# Derive the tap name (user/tap) from the tap repo's origin URL, e.g.
# github.com/henryle97/homebrew-tap -> henryle97/tap.
TAP="$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/homebrew-([^/]+)\.git$|\1/\2|; s|.*[:/]([^/]+)/homebrew-([^/]+)$|\1/\2|')"
if [[ "$TAP" == *[:.]* || "$TAP" == */*/* ]]; then TAP=""; fi
if [[ -n "$TAP" ]]; then
    echo "  next: brew audit --cask $TAP/lookaround && brew style $CASK"
    echo "  (avoid audit --new — it demands a Gatekeeper signature this app never has)"
fi
echo "  then: git commit -am 'lookaround $VERSION' && git push"
