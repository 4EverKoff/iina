#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP="Xtream-Launcher.app"
BIN="$APP/Contents/MacOS/Xtream-Launcher"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 \
  -target arm64-apple-macos13.0 \
  -o "$BIN" \
  Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Build OK : $APP"
