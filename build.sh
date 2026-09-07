#!/bin/zsh
# Build LookAround as a native macOS menu-bar .app using only swiftc
# (avoids SwiftPM manifest linking; works with Command Line Tools only).
set -euo pipefail
cd "$(dirname "$0")"

APP="LookAround.app"
BIN="$APP/Contents/MacOS/LookAround"
# SDK lookup: allow override, then CLT path (local), then active toolchain
# (GitHub runners and full-Xcode machines where the CLT dir may not exist).
if [[ -n "${MACOSX_SDK:-}" ]]; then
  SDK="$MACOSX_SDK"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
else
  SDK="$(xcrun --show-sdk-path)"
fi

echo "→ compiling…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -O \
  -o "$BIN" \
  Sources/LookAround/*.swift

echo "→ bundling…"
cp Sources/LookAround/Resources/Info.plist "$APP/Contents/Info.plist"
cp Sources/LookAround/Resources/*.icns "$APP/Contents/Resources/" 2>/dev/null || true
cp Sources/LookAround/Resources/BreakPrompts.json "$APP/Contents/Resources/BreakPrompts.json"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc sign so the .app launches on Apple Silicon via Finder.
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ built: $APP"
echo "  run: open $APP"
