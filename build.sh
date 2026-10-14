#!/bin/sh
# Builds "Finicky Picker.app" into ~/Applications.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Finicky Picker.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/Finicky Picker" "$SRC/Picker.swift"
cp "$SRC/learn.py" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>social.topc.finicky-picker</string>
  <key>CFBundleName</key><string>Finicky Picker</string>
  <key>CFBundleExecutable</key><string>Finicky Picker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP" 2>/dev/null
echo "Built $APP"
