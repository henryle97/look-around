#!/bin/zsh
# Build axdrive, the Accessibility-based UI driver used to test LookAround
# without Xcode/XCUITest (see AGENTS.md).
set -euo pipefail
cd "$(dirname "$0")"

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

echo "→ compiling axdrive…"
swiftc -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -O \
  -o axdrive \
  main.swift

echo "✓ built: tools/axdrive/axdrive"
