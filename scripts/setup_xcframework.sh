#!/bin/bash

# newtypesdk_demo_ios/scripts/setup_xcframework.sh
# Copies the XCFramework from newtypesdk_ios to this demo project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SDK_PROJECT_DIR="$(dirname "$PROJECT_DIR")/newtypesdk_ios"
SDK_DIST_DIR="$SDK_PROJECT_DIR/dist"
DEMO_LIBS_DIR="$PROJECT_DIR/libs"

echo "=== Setting up NewTypeSDK XCFramework ==="
echo "Demo Project: $PROJECT_DIR"
echo "SDK Project: $SDK_PROJECT_DIR"
echo "SDK Dist: $SDK_DIST_DIR"
echo "Demo Libs: $DEMO_LIBS_DIR"

# Check if XCFramework exists in SDK dist
if [ ! -d "$SDK_DIST_DIR/NewTypeSDK.xcframework" ]; then
    echo ""
    echo "XCFramework not found in SDK dist directory."
    echo "Please build the XCFramework first:"
    echo "  cd $SDK_PROJECT_DIR/scripts"
    echo "  ./build_xcframework.sh"
    exit 1
fi

# Create libs directory if it doesn't exist
mkdir -p "$DEMO_LIBS_DIR"

# Remove existing XCFramework
if [ -d "$DEMO_LIBS_DIR/NewTypeSDK.xcframework" ]; then
    echo "Removing existing XCFramework..."
    rm -rf "$DEMO_LIBS_DIR/NewTypeSDK.xcframework"
fi

# Copy XCFramework
echo "Copying XCFramework..."
cp -R "$SDK_DIST_DIR/NewTypeSDK.xcframework" "$DEMO_LIBS_DIR/"

# Verify
if [ -d "$DEMO_LIBS_DIR/NewTypeSDK.xcframework" ]; then
    echo "✓ XCFramework copied successfully"
    echo ""
    echo "XCFramework contents:"
    ls -la "$DEMO_LIBS_DIR/NewTypeSDK.xcframework"
    echo ""
    echo "=== Setup Complete ==="
    echo ""
    echo "Next steps:"
    echo "1. cd $PROJECT_DIR"
    echo "2. pod install"
    echo "3. open newtypesdk_demo_ios.xcworkspace"
else
    echo "✗ Failed to copy XCFramework"
    exit 1
fi
