#!/bin/zsh
# Package LookAround.app into a versioned, distributable DMG.
#
# Usage:
#   ./scripts/package-dmg.sh [--version 1.0.0] [--no-build]
#
# - --version is the single source of truth for a release: it stamps
#   Sources/LookAround/Resources/Info.plist's CFBundleShortVersionString
#   before building (so a git tag always drives what ships), and refuses
#   to go backwards if the checked-in plist already has a higher version
#   (catches a stale/wrong tag instead of silently downgrading it).
#   Without --version, the current plist value is used as-is.
# - Unless --no-build, runs ./build.sh first so the .app is fresh.
# - Output: dist/LookAround-<version>.dmg (+ .sha256 sidecar).
#
# DMG layout: tries a polished Finder layout via `npx create-dmg`
# (unsigned — this project distributes unsigned, forever) and falls back
# to a plain hdiutil image (classic /LookAround.app + /Applications
# symlink) if create-dmg is unavailable or fails, so a layout-tool flake
# can never break a release.
set -euo pipefail
setopt null_glob
cd "$(dirname "$0")/.."

PLIST="Sources/LookAround/Resources/Info.plist"
VERSION=""
NO_BUILD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --no-build) NO_BUILD=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

CURRENT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")

if [[ -z "$VERSION" ]]; then
    VERSION="$CURRENT"
else
    VERSION="${VERSION#v}"  # allow a leading "v" (e.g. from a git tag)
    if [[ "$VERSION" != "$CURRENT" ]]; then
        # Numeric X.Y.Z compare: refuse to stamp backwards over a plist
        # that's already ahead (a real drift signal, not just "different").
        # Split into arrays, not `read -r a b c`: zsh assigns the whole
        # remainder to the last name, so the patch component would come
        # out as "0.0.0" and the arithmetic below would abort ("bad
        # floating point constant") — which, as an `if` condition, reads
        # as false and silently defeats this very guard. Each component
        # is trimmed at its first non-digit so a prerelease tag
        # (1.0.0-rc.1) compares on its numeric part.
        IFS='.' read -rA cparts <<< "${CURRENT}.0.0"
        IFS='.' read -rA vparts <<< "${VERSION}.0.0"
        cM="${cparts[1]%%[^0-9]*}"; cm="${cparts[2]%%[^0-9]*}"; cp="${cparts[3]%%[^0-9]*}"
        vM="${vparts[1]%%[^0-9]*}"; vm="${vparts[2]%%[^0-9]*}"; vp="${vparts[3]%%[^0-9]*}"
        cM="${cM:-0}"; cm="${cm:-0}"; cp="${cp:-0}"
        vM="${vM:-0}"; vm="${vm:-0}"; vp="${vp:-0}"
        if (( cM > vM || (cM == vM && cm > vm) || (cM == vM && cm == vm && cp > vp) )); then
            echo "✗ tag version $VERSION is behind Info.plist's $CURRENT — check the tag" >&2
            exit 1
        fi
        echo "→ stamping Info.plist: $CURRENT → $VERSION"
        # A plain text substitution (not PlistBuddy/plutil -replace, which
        # both rewrite the whole file — alphabetized keys, tabs — turning
        # a one-line version bump into a full-file diff).
        sed -i '' -E "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]*</string>|<string>${VERSION}</string>|;}" "$PLIST"
    fi
fi

APP="LookAround.app"
DMG_NAME="LookAround-${VERSION}.dmg"
STAGE="dist/dmg-staging"
OUT="dist/${DMG_NAME}"

if [[ $NO_BUILD -eq 0 ]]; then
    ./build.sh
fi
if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found — run ./build.sh first" >&2
    exit 1
fi

mkdir -p dist
rm -f "$OUT" "${OUT}.sha256"
BUILT=0

if command -v npx >/dev/null 2>&1; then
    echo "→ creating DMG (create-dmg, unsigned)…"
    rm -f dist/LookAround\ *.dmg
    LOG=$(mktemp)
    if npx --yes create-dmg@7 "$APP" dist --no-code-sign --overwrite >"$LOG" 2>&1; then
        PRODUCED=$(ls dist/LookAround\ *.dmg 2>/dev/null | head -1)
        if [[ -n "$PRODUCED" ]]; then
            mv "$PRODUCED" "$OUT"
            BUILT=1
        fi
    fi
    if [[ $BUILT -eq 0 ]]; then
        echo "⚠ create-dmg failed, falling back to plain hdiutil layout:"
        tail -20 "$LOG"
    fi
    rm -f "$LOG"
else
    echo "⚠ npx not found, using plain hdiutil layout"
fi

if [[ $BUILT -eq 0 ]]; then
    echo "→ staging $DMG_NAME (version $VERSION)…"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"

    echo "→ creating DMG (hdiutil)…"
    hdiutil create \
        -volname "LookAround" \
        -srcfolder "$STAGE" \
        -ov \
        -format UDZO \
        "$OUT" >/dev/null
    rm -rf "$STAGE"
fi

echo "→ verifying artifact…"
codesign --verify --deep --strict "$APP" \
    && echo "  ✓ ad-hoc code signature intact" \
    || { echo "✗ codesign verification failed" >&2; exit 1; }
SPCTL_OUT=$(spctl -a -t exec -vv "$APP" 2>&1) || true
if echo "$SPCTL_OUT" | grep -q "rejected"; then
    echo "  ℹ Gatekeeper rejects it (expected — unsigned by design)"
else
    echo "  ℹ unexpected Gatekeeper verdict for an unsigned app:"
    echo "$SPCTL_OUT" | sed 's/^/    /'
fi

SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
echo "$SHA  $DMG_NAME" > "${OUT}.sha256"
(cd dist && shasum -a 256 -c "${DMG_NAME}.sha256" >/dev/null) \
    && echo "  ✓ sha256 sidecar round-trips" \
    || { echo "✗ sha256 self-check failed" >&2; exit 1; }

echo "✓ built: $OUT"
echo "  sha256: $SHA"
echo "  upload to: GitHub → Releases → v${VERSION}"
