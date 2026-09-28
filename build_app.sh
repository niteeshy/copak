#!/usr/bin/env bash
set -e

UNIVERSAL=false
CREATE_ZIP=false
SOURCE_ICON=""

for arg in "$@"; do
    case "$arg" in
        --universal)
            UNIVERSAL=true
            ;;
        --zip)
            CREATE_ZIP=true
            ;;
        --source=*)
            SOURCE_ICON="${arg#*=}"
            ;;
        *)
            if [ -f "$arg" ]; then
                SOURCE_ICON="$arg"
            fi
            ;;
    esac
done

if [ "$UNIVERSAL" = true ]; then
    echo "Building Copak universal release binary (arm64 + x86_64)..."
    swift build -c release --arch arm64 --arch x86_64
else
    echo "Building Copak release binary..."
    swift build -c release
fi

# Check binary location
BINARY=""
if [ -f ".build/out/Products/Release/Copak" ]; then
    BINARY=".build/out/Products/Release/Copak"
elif [ -f ".build/release/Copak" ]; then
    BINARY=".build/release/Copak"
elif [ -f ".build/release/ContextPacket" ]; then
    BINARY=".build/release/ContextPacket"
elif [ -f ".build/out/Products/Release/ContextPacket" ]; then
    BINARY=".build/out/Products/Release/ContextPacket"
else
    echo "Error: Release binary not found in .build/release or .build/out/Products/Release"
    exit 1
fi

echo "Generating and preparing standardized macOS AppIcon..."
ICON_ARG=""
if [ -n "$SOURCE_ICON" ]; then
    ICON_ARG="--source $SOURCE_ICON"
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

if [ "$CREATE_ZIP" = true ]; then
    echo "Creating Copak.zip distribution archive..."
    rm -f Copak.zip
    ditto -c -k --sequesterRsrc --keepParent Copak.app Copak.zip
    echo "✓ Copak.zip created successfully!"
fi
