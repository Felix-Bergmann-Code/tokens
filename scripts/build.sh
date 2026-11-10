#!/bin/zsh
# Builds Tokens.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Tokens.app
VERSION=1.0.0

swift build -c release

[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources/AppIcon.icns

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tokens "$APP/Contents/MacOS/Tokens"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tokens</string>
    <key>CFBundleDisplayName</key><string>Tokens</string>
    <key>CFBundleIdentifier</key><string>io.github.felix-bergmann-code.tokens</string>
    <key>CFBundleExecutable</key><string>Tokens</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Local token analytics for coding agents.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    pkill -x Tokens 2>/dev/null || true
    rm -rf ~/Applications/Tokens.app
    cp -R "$APP" ~/Applications/Tokens.app
    open ~/Applications/Tokens.app
    echo "Installed to ~/Applications/Tokens.app"
fi
