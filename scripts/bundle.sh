#!/bin/sh
# Builds build/Spotty.app: a universal (Apple silicon + Intel) release build, wrapped in a bundle
# and ad-hoc signed.
#
#   scripts/bundle.sh            # version 0.1.0
#   scripts/bundle.sh 1.2.0      # or VERSION=1.2.0 scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:-${VERSION:-0.1.0}}

swift build -c release --arch arm64 --arch x86_64 --product Spotty
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Spotty"

app=build/Spotty.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Spotty"

# The icon: Resources/AppIcon.icon (Icon Composer's layered format) compiled by actool into
# Assets.car for macOS 26 and later, plus an AppIcon.icns it renders for macOS 14 and 15. Without
# actool (Command Line Tools only), the checked-in AppIcon.icns is used as it is.
icon=""
mkdir -p "$app/Contents/Resources"
if [ -d Resources/AppIcon.icon ] && xcrun --find actool >/dev/null 2>&1; then
    xcrun actool Resources/AppIcon.icon --compile "$app/Contents/Resources" --platform macosx \
        --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist "$(mktemp -t spotty-icon).plist" >/dev/null
    icon="<key>CFBundleIconFile</key><string>AppIcon</string><key>CFBundleIconName</key><string>AppIcon</string>"
elif [ -f Resources/AppIcon.icns ]; then
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

# Refuse to call it built unless it is complete: an earlier run once left an unsigned app
# without its icon when actool failed quietly.
fail() { echo "bundle.sh: $1" >&2; exit 1; }
codesign --verify --deep --strict "$app" || fail "the signature does not verify"
[ -f "$app/Contents/Resources/Assets.car" ] || [ -f "$app/Contents/Resources/AppIcon.icns" ] || fail "the icon is missing"
archs=$(lipo -archs "$app/Contents/MacOS/Spotty")
case " $archs " in *" arm64 "*) ;; *) fail "no arm64 in the binary ($archs)" ;; esac
case " $archs " in *" x86_64 "*) ;; *) fail "no x86_64 in the binary ($archs)" ;; esac
[ "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" = "$version" ] || fail "the version is not $version"
echo "Built $app $version ($archs)"
