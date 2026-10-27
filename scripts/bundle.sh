#!/bin/sh
# Builds build/Spotty.app: a release build, wrapped in a bundle and ad-hoc signed.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product Spotty
bin="$(swift build -c release --show-bin-path)/Spotty"

app=build/Spotty.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Spotty"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.hus.spotty</string>
    <key>CFBundleName</key><string>Spotty</string>
    <key>CFBundleDisplayName</key><string>Spotty</string>
    <key>CFBundleExecutable</key><string>Spotty</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>0.1</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app"
