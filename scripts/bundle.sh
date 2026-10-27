#!/bin/sh
# Builds build/Spotty.app: a universal (Apple silicon + Intel) release build, wrapped in a bundle
# and ad-hoc signed.
#
#   scripts/bundle.sh            # version 0.1.0
#   scripts/bundle.sh 1.2.0      # or VERSION=1.2.0 scripts/bundle.sh
set -eu
cd "$(dirname "$0")/.."
version=${1:-${VERSION:-0.1.0}}

swift build -c release --arch arm64 --arch x86_64 --product Spotty
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Spotty"

app=build/Spotty.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Spotty"

icon=""
if [ -f Resources/AppIcon.icns ]; then
    mkdir -p "$app/Contents/Resources"
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    icon="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

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
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    $icon
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app"
echo "Built $app $version ($(lipo -archs "$app/Contents/MacOS/Spotty"))"
