#!/bin/zsh
# Publish a LookAround release from a local machine — an alternative to
# pushing a git tag and letting .github/workflows/release.yml do it in CI.
#
# Gated by GitHub permission, not just local access: only the account
# with ADMIN permission on the repo (checked live via `gh api`, not a
# hardcoded username) may publish. Anyone else's `gh` login is refused
# before anything is built.
#
# Usage:
#   ./scripts/release-local.sh [--version 1.0.0] [--yes]
#
# - --version: same contract as package-dmg.sh (defaults to Info.plist's
#   CFBundleShortVersionString; stamps the plist forward, refuses to go
#   backwards over it — see package-dmg.sh's own header comment).
# - --yes: skip the confirmation prompt (for scripted use).
#
# What it does NOT do that CI does: attach a build-provenance attestation
# (actions/attest-build-provenance needs GitHub Actions' OIDC token, which
# isn't available on a laptop). Prefer `git tag vX && git push origin vX`
# when provenance matters; the CI job checks for an existing release
# first, so publishing locally and later pushing the same tag is safe —
# CI will see the release already exists and skip cleanly.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=""
CONFIRM=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --yes) CONFIRM=0; shift ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

command -v gh >/dev/null 2>&1 || { echo "✗ gh CLI not found — https://cli.github.com" >&2; exit 1; }

echo "→ checking GitHub permission…"
REPO_JSON=$(gh repo view --json owner,name,viewerPermission)
OWNER=$(echo "$REPO_JSON" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["owner"]["login"])')
NAME=$(echo "$REPO_JSON" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
PERM=$(echo "$REPO_JSON" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["viewerPermission"])')
USER=$(gh api user --jq .login)

if [[ "$PERM" != "ADMIN" ]]; then
    echo "✗ $USER has '$PERM' permission on $OWNER/$NAME — releasing requires ADMIN." >&2
    echo "  This is checked live via the GitHub API, not a local setting; ask an admin to release, or grant admin access first." >&2
    exit 1
fi
echo "✓ $USER is ADMIN on $OWNER/$NAME"

if [[ -z "$VERSION" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
        Sources/LookAround/Resources/Info.plist)
fi
VERSION="${VERSION#v}"

if gh release view "v${VERSION}" >/dev/null 2>&1; then
    echo "✗ v${VERSION} is already released: $(gh release view "v${VERSION}" --json url -q .url)" >&2
    exit 1
fi

./scripts/package-dmg.sh --version "$VERSION"

DMG="dist/LookAround-${VERSION}.dmg"
SHA=$(awk '{print $1}' "${DMG}.sha256")

echo
echo "About to publish as ${OWNER}/${NAME}:"
echo "  tag:     v${VERSION}"
echo "  dmg:     $DMG"
echo "  sha256:  $SHA"
echo "  as user: $USER (ADMIN)"
echo "This creates a public GitHub Release — it will be visible immediately."
if [[ $CONFIRM -eq 1 ]]; then
    printf "Continue? [y/N] "
    read -r REPLY
    [[ "$REPLY" == [yY]* ]] || { echo "aborted"; exit 1; }
fi

NOTES=$(mktemp)
sed -e "s/__VERSION__/${VERSION}/g" packaging/homebrew/RELEASE-NOTES.md > "$NOTES"
gh release create "v${VERSION}" \
    --title "LookAround v${VERSION}" \
    --notes-file "$NOTES" \
    "${DMG}#LookAround-${VERSION}.dmg"

sed -e "s/^  version .*/  version \"${VERSION}\"/" \
    -e "s/^  sha256 .*/  sha256 \"${SHA}\"/" \
    packaging/homebrew/Casks/lookaround.rb > dist/lookaround.rb

echo
echo "✓ published: $(gh release view "v${VERSION}" --json url -q .url)"
echo "  Cask update staged at dist/lookaround.rb — apply it with:"
echo "    ./scripts/bump-cask.sh ${VERSION}   (run from your homebrew-tap checkout)"
