#!/bin/zsh
# Build benchprobe, the resource-counter sampler used by scripts/bench.sh
# (see docs/benchmarking.md). CLT-only, same as build.sh and axdrive.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "${MACOSX_SDK:-}" ]]; then
  SDK="$MACOSX_SDK"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
else
  SDK="$(xcrun --show-sdk-path)"
fi

echo "→ compiling benchprobe…"
swiftc -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -O \
  -o benchprobe \
  main.swift

echo "✓ built: tools/benchprobe/benchprobe"
