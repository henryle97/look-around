#!/bin/zsh
# Unit tests for LookAround's pure logic (scheduling rules, settings
# persistence, decode fallbacks — see docs/unit-testing.md for what's in
# scope and why).
#
# No XCTest/`swift test` here: this repo is Xcode-free (see build.sh) and
# the CLT-only SwiftPM linker can't even parse Package.swift. Instead this
# compiles Tests/LookAroundTests + a handful of dependency-free
# Sources/LookAround files into one standalone binary with swiftc — same
# approach as tools/axdrive — and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${MACOSX_SDK:-}" ]]; then
  SDK="$MACOSX_SDK"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
else
  SDK="$(xcrun --show-sdk-path)"
fi

# Only files with no dependency on AppKit-heavy UI/scheduler code (no
# BreakScheduler.swift, no view files, no @main) — see docs/unit-testing.md
# before adding a Sources file here.
SOURCES=(
  Sources/LookAround/Models.swift
  Sources/LookAround/SmartPause.swift
  Sources/LookAround/ActivityProbe.swift
  Sources/LookAround/Helpers.swift
  Sources/LookAround/SettingsStore.swift
)

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
BIN="$BUILD_DIR/LookAroundTests"

echo "→ compiling unit tests…"
swiftc -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -o "$BIN" \
  "${SOURCES[@]}" \
  Tests/LookAroundTests/*.swift

echo "→ running…"
echo ""
"$BIN"
