#!/bin/bash
# Builds Diroid.app from source: compiles the Swift package, assembles a
# proper macOS app bundle around it using Resources/Info.plist and
# Resources/Diroid.icns, and ad-hoc code-signs it (no Apple Developer
# account needed — this is enough to run locally, but macOS will flag the app
# as untrusted if you hand it to someone else's Mac).
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Compiling..."
swift build -c release

APP="Diroid.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Diroid "$APP/Contents/MacOS/Diroid"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Diroid.icns "$APP/Contents/Resources/Diroid.icns"

echo "==> Code-signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "==> Done: $APP"
