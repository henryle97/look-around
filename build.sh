#!/bin/zsh
# Build LookAround as a native macOS menu-bar .app using only swiftc
# (avoids SwiftPM manifest linking; works with Command Line Tools only).
set -euo pipefail
cd "$(dirname "$0")"

APP="LookAround.app"
BIN="$APP/Contents/MacOS/LookAround"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

echo "→ compiling…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -O \
  -o "$BIN" \
  Sources/LookAround/*.swift

echo "→ bundling…"
cp Sources/LookAround/Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc sign so the .app launches on Apple Silicon via Finder.
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ built: $APP"
echo "  run: open $APP"
