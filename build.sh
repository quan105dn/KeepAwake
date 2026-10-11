#!/bin/bash
# Build KeepAwake.app with the Xcode Command Line Tools (full Xcode not required).
#
#   ./build.sh            build ./build/KeepAwake.app
#   ./build.sh install    build, install to /Applications and launch
#   ./build.sh release    build and package ./build/KeepAwake-v<version>-macos-arm64.zip (+ .sha256)
#
# The version comes from the VERSION file; the build number is the git commit count.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(tr -d '[:space:]' < VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=build/KeepAwake.app

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Compiling KeepAwake $VERSION ($BUILD)…"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -framework SwiftUI -framework IOKit -framework ServiceManagement \
  Sources/*.swift -o "$APP/Contents/MacOS/KeepAwake"

cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

echo "▸ Icon…"
ICONSET=build/AppIcon.iconset && mkdir -p "$ICONSET"
swift Resources/make_icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep -s - "$APP"
echo "✓ $APP"

case "${1:-}" in
  install)
    pkill -x KeepAwake 2>/dev/null || true
    # Wait for the old instance to exit, otherwise `open` may just re-activate the dying process.
    for _ in $(seq 50); do pgrep -x KeepAwake >/dev/null || break; sleep 0.1; done
    rm -rf /Applications/KeepAwake.app
    cp -R "$APP" /Applications/
    open /Applications/KeepAwake.app
    echo "✓ Installed to /Applications and launched"
    ;;
  release)
    ZIP="build/KeepAwake-v$VERSION-macos-arm64.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    (cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
    echo "✓ $ZIP"
    cat "$ZIP.sha256"
    ;;
esac
