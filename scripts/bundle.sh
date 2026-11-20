#!/usr/bin/env bash
# Builds Linkroute and wraps the binary in a signed .app bundle at build/Linkroute.app.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG" --product Linkroute
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Linkroute"

APP=build/Linkroute.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Linkroute"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi

# Hardened runtime blocks code injection (e.g. DYLD_INSERT_LIBRARIES) into the process that
# sees every link you click. Ad-hoc signature by default; set SIGN_IDENTITY for a real one.
codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
