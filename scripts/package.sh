#!/bin/sh
# Builds dist/TaskManager.app (arm64 + x86_64) and dist/TaskManager-macOS.zip.
# The app is ad-hoc signed only (no Developer ID, not notarized).
set -e
cd "$(dirname "$0")/.."
VERSION=1.0.0
rm -rf dist && mkdir -p dist

swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0

APP=dist/TaskManager.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  .build/arm64-apple-macosx/release/TaskManager \
  .build/x86_64-apple-macosx/release/TaskManager \
  -output "$APP/Contents/MacOS/TaskManager"
cp packaging/Info.plist "$APP/Contents/Info.plist"

swift scripts/make-icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf dist/AppIcon.iconset

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "dist/TaskManager-$VERSION-macOS.zip"
shasum -a 256 "dist/TaskManager-$VERSION-macOS.zip"
