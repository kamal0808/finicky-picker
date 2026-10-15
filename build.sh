#!/bin/sh
# Builds "Profiley.app" into ~/Applications.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Profiley.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/Profiley" "$SRC/Profiley.swift"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.kamalkhatwani.profiley</string>
  <key>CFBundleName</key><string>Profiley</string>
  <key>CFBundleExecutable</key><string>Profiley</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Web site URL</string>
    <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>HTML document</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.html</string><string>public.xhtml</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force -s - "$APP" 2>/dev/null
echo "Built $APP"
