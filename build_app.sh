#!/usr/bin/env bash
set -e

echo "Building Copak release binary..."
swift build -c release

# Check binary location
BINARY=""
if [ -f ".build/release/Copak" ]; then
    BINARY=".build/release/Copak"
elif [ -f ".build/release/ContextPacket" ]; then
    BINARY=".build/release/ContextPacket"
else
    echo "Error: Release binary not found in .build/release"
    exit 1
fi

echo "Generating and preparing standardized macOS AppIcon..."
ICON_ARG=""
if [ -n "$1" ] && [ -f "$1" ]; then
    ICON_ARG="--source $1"
fi
if [ -f "scripts/generate_app_icon.py" ]; then
    /usr/bin/python3 scripts/generate_app_icon.py $ICON_ARG 2>/dev/null || python3 scripts/generate_app_icon.py $ICON_ARG 2>/dev/null || true
fi

echo "Creating Copak.app bundle..."
mkdir -p Copak.app/Contents/MacOS
mkdir -p Copak.app/Contents/Resources

cp "$BINARY" Copak.app/Contents/MacOS/Copak
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns Copak.app/Contents/Resources/AppIcon.icns
fi
if [ -f "Resources/Copak.png" ]; then
    cp Resources/Copak.png Copak.app/Contents/Resources/Copak.png
fi

cat << 'EOF' > Copak.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Copak</string>
    <key>CFBundleIdentifier</key>
    <string>com.copak.app</string>
    <key>CFBundleName</key>
    <string>Copak</string>
    <key>CFBundleDisplayName</key>
    <string>Copak</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# Touch bundle and clear extended attributes so macOS LaunchServices picks up new icon and metadata
xattr -cr Copak.app 2>/dev/null || true
touch Copak.app

echo "✓ Copak.app created successfully with updated icon and metadata!"
echo "You can open it anytime with: open Copak.app"
