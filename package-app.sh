#!/bin/bash
# Build and bundle shitty-shortcuts.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=shitty-shortcuts.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ShittyShortcuts "$APP/Contents/MacOS/shitty-shortcuts"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>shitty-shortcuts</string>
  <key>CFBundleIdentifier</key><string>com.januschka.shitty-shortcuts</string>
  <key>CFBundleExecutable</key><string>shitty-shortcuts</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>shitty-shortcuts records short voice clips for whisper transcription.</string>
</dict>
</plist>
EOF

codesign --force --deep -s - "$APP"
echo "built $APP"
