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

echo "Generating and preparing AppIcon..."
ICON_SRC="/Users/niteesh/Downloads/Copak.png"
if [ ! -f "$ICON_SRC" ] && [ -f "Resources/Copak.png" ]; then
    ICON_SRC="Resources/Copak.png"
fi

if [ -f "$ICON_SRC" ]; then
    mkdir -p /tmp/CopakIcon.iconset
    sips -z 16 16     "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_16x16.png > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_16x16@2x.png > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_32x32.png > /dev/null 2>&1
    sips -z 64 64     "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_32x32@2x.png > /dev/null 2>&1
    sips -z 128 128   "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_128x128.png > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_128x128@2x.png > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_256x256.png > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_256x256@2x.png > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_512x512.png > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_SRC" --out /tmp/CopakIcon.iconset/icon_512x512@2x.png > /dev/null 2>&1
    iconutil -c icns /tmp/CopakIcon.iconset -o Resources/AppIcon.icns
    rm -rf /tmp/CopakIcon.iconset
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
