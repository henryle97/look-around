#!/bin/zsh
# End-to-end validation for the lookaround Homebrew Cask:
#   audit + style + install (isolated) + uninstall --zap.
#
# Usage:
#   ./scripts/test-cask.sh [--version 0.1.0]
#
# - Version defaults to CFBundleShortVersionString in Info.plist.
# - Builds dist/LookAround-<version>.dmg first unless it already exists,
#   then stamps a throwaway copy of the Cask template with that DMG's
#   real version + sha256 and validates the result inside an ephemeral
#   local tap (created with `brew tap-new`, removed afterwards), because
#   `brew audit` only accepts cask names, not file paths.
# - The test copy points `url` at the local DMG via file:// so audit's
#   download + sha256 check and the install round-trip exercise the exact
#   bytes we built, with no published GitHub Release required. The real
#   URL template is asserted separately (exact-match grep on the
#   interpolation pattern, plus a non-fatal HEAD request).
# - Install targets an isolated --appdir temp dir, so /Applications is
#   never touched. If you have real LookAround settings
#   (~/Library/Preferences/com.lookaround.app.plist), they are backed up
#   before the --zap step and restored afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done
if [[ -z "$VERSION" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
        Sources/LookAround/Resources/Info.plist)
fi
VERSION="${VERSION#v}"

DMG="dist/LookAround-${VERSION}.dmg"
if [[ ! -f "$DMG" ]]; then
    echo "→ no $DMG, packaging…"
    ./scripts/package-dmg.sh --version "$VERSION"
fi
SHA=$(awk '{print $1}' "${DMG}.sha256")

TAP="lookaround-test/tap"
WORK=$(mktemp -d)
cleanup() {
    brew untap "$TAP" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "→ scaffolding ephemeral tap $TAP…"
brew tap-new "$TAP" >/dev/null
TAPDIR=$(brew --repo "$TAP")
mkdir -p "$TAPDIR/Casks"
sed -e "s/^  version .*/  version \"${VERSION}\"/" \
    -e "s/^  sha256 .*/  sha256 \"${SHA}\"/" \
    -e "s|^  url .*|  url \"file://${PWD}/${DMG}\"|" \
    packaging/homebrew/Casks/lookaround.rb > "$TAPDIR/Casks/lookaround.rb"

echo "→ asserting real URL template…"
grep -qF 'releases/download/v#{version}/LookAround-#{version}.dmg' \
    packaging/homebrew/Casks/lookaround.rb \
    || { echo "✗ url template lost its version interpolation" >&2; exit 1; }
REAL_URL="https://github.com/henryle97/look-around/releases/download/v${VERSION}/LookAround-${VERSION}.dmg"
if curl -sfI -o /dev/null --max-time 15 "$REAL_URL"; then
    echo "✓ release asset reachable: $REAL_URL"
else
    echo "⚠ release asset not reachable (expected before first release): $REAL_URL"
fi

echo "→ brew audit…"
# --except=sha256_no_check_if_unversioned: audit reads the file:// test
# URL as "unversioned"; the real versioned https URL is asserted above.
# Deliberately the default (non---new) audit: --new/--online additionally
# demands a published release (downloadable asset, livecheck hit) and a
# live homepage, which cannot exist before the first release. Signature
# verification is skipped by policy: distribution stays unsigned forever
# (default audit does not check signatures).
brew audit --cask --except=sha256_no_check_if_unversioned "$TAP/lookaround"
echo "→ brew style…"
brew style "$TAPDIR/Casks/lookaround.rb"

echo "→ checking homepage…"
if curl -sfI -o /dev/null --max-time 15 "https://henryle97.github.io/look-around/"; then
    echo "✓ homepage reachable"
else
    echo "⚠ homepage not reachable (enable Pages: repo Settings → Pages → main → /docs)"
fi

APPDIR="$WORK/appdir"
mkdir -p "$APPDIR"
echo "→ brew install (appdir=$APPDIR)…"
brew install --cask --appdir="$APPDIR" "$TAP/lookaround"
if [[ ! -d "$APPDIR/LookAround.app" ]]; then
    echo "✗ expected $APPDIR/LookAround.app after install" >&2
    exit 1
fi
echo "✓ installed: $APPDIR/LookAround.app"

PLIST="$HOME/Library/Preferences/com.lookaround.app.plist"
BACKUP="$WORK/plist.backup"
HAD_PLIST=0
if [[ -f "$PLIST" ]]; then
    HAD_PLIST=1
    cp "$PLIST" "$BACKUP"
    echo "→ backed up existing settings plist"
fi

echo "→ brew uninstall --zap…"
brew uninstall --cask --zap "$TAP/lookaround"
if [[ -e "$PLIST" ]]; then
    echo "✗ zap left $PLIST behind" >&2
    exit 1
fi
echo "✓ zap removed settings plist"

if [[ $HAD_PLIST -eq 1 ]]; then
    cp "$BACKUP" "$PLIST"
    echo "→ restored existing settings plist"
fi

echo "✓ cask OK (audit + style + install + uninstall --zap)"
