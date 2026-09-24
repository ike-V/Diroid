#!/bin/bash
# Builds and ad-hoc signs Diroid.app. Ad-hoc signing runs locally; other Macs
# will flag the app as untrusted.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Compiling..."
swift build -c release

APP="Diroid.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Diroid "$APP/Contents/MacOS/Diroid"
# Sets the minimum macOS (13.0) and the SDK version (the installed one).
vtool -set-build-version macos 13.0 "$(xcrun --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/Diroid" "$APP/Contents/MacOS/Diroid"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Diroid.icns "$APP/Contents/Resources/Diroid.icns"

echo "==> Code-signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "==> Done: $APP"
