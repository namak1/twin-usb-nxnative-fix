#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="../outputs/Twin Controller Studio.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
clang -O2 -Wall -Wextra -Wno-unused-function -fobjc-arc -fblocks App.m UniversalBridge.m -framework Cocoa -framework WebKit -framework IOKit -framework GameController -o "$app/Contents/MacOS/TwinControllerStudio"
cp index.html mapper.js REFERENCE-LICENSE "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>TwinControllerStudio</string><key>CFBundleIdentifier</key><string>local.twinfix.controllerstudio</string><key>CFBundleName</key><string>Twin Controller Studio</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>3.1</string><key>CFBundleVersion</key><string>4</string><key>LSMinimumSystemVersion</key><string>12.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$app"
