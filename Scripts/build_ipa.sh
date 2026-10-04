#!/bin/bash
# ==============================================================================
# NetScan - iOS IPA Build and Packaging Script
# Builds NetScan into an installable .ipa ready for AltStore or Sideloadly.
# ==============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETSCAN_DIR="$PROJECT_DIR/NetScan"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/NetScan.xcarchive"
EXPORT_DIR="$BUILD_DIR/Export"
IPA_PATH="$PROJECT_DIR/NetScan.ipa"

echo "=== Building NetScan iOS App for AltStore ==="
echo "Project Directory: $NETSCAN_DIR"

if command -v xcodebuild >/dev/null 2>&1; then
    echo "Xcode detected. Starting xcodebuild archive..."
    mkdir -p "$BUILD_DIR"
    
    # 1. Archive the project
    xcodebuild archive \
        -project "$NETSCAN_DIR/NetScan.xcodeproj" \
        -scheme "NetScan" \
        -configuration "Release" \
        -sdk iphoneos \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO
        
    echo "Archive completed: $ARCHIVE_PATH"
    
    # 2. Package into Payload structure
    APP_BUNDLE=$(find "$ARCHIVE_PATH/Products/Applications" -name "*.app" | head -n 1)
    if [ -d "$APP_BUNDLE" ]; then
        PAYLOAD_DIR="$BUILD_DIR/Payload"
        rm -rf "$PAYLOAD_DIR"
        mkdir -p "$PAYLOAD_DIR"
        cp -R "$APP_BUNDLE" "$PAYLOAD_DIR/"
        
        # Zip into NetScan.ipa
        cd "$BUILD_DIR"
        zip -qr "$IPA_PATH" Payload
        echo "Successfully created NetScan.ipa at $IPA_PATH"
    else
        echo "Error: Could not locate .app bundle inside archive."
        exit 1
    fi
else
    echo "xcodebuild not found in this environment (Linux/WSL)."
    echo "Using Python packaging fallback to build AltStore-ready IPA bundle..."
    python3 "$PROJECT_DIR/Scripts/package_ipa.py"
fi

echo "=== Packaging Complete ==="
echo "You can sideload NetScan.ipa onto your iPhone using AltStore, AltServer, or Sideloadly."
