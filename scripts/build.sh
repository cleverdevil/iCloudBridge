#!/bin/bash
set -e

# iCloud Bridge Build Script
# Builds a proper macOS .app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="iCloud Bridge"
BUNDLE_NAME="iCloudBridge"
BUNDLE_ID="com.cleverdevil.iCloudBridge"
BUILD_DIR="$PROJECT_ROOT/.build"
APP_BUNDLE="$PROJECT_ROOT/build/${BUNDLE_NAME}.app"
RESOURCES_DIR="$PROJECT_ROOT/Sources/iCloudBridge/Resources"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_status() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Parse arguments
INSTALL=false
CLEAN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            INSTALL=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --install    Install to /Applications after building"
            echo "  --clean      Clean build artifacts before building"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT"

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo_status "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    rm -rf "$PROJECT_ROOT/build"
fi

# Build the release binary
echo_status "Building release binary..."
swift build -c release

# Create the app bundle structure
echo_status "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the binary
echo_status "Copying binary..."
cp "$BUILD_DIR/release/$BUNDLE_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
echo_status "Copying Info.plist..."
cp "$RESOURCES_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Copy app icon
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    echo_status "Copying app icon..."
    cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo_status "Creating PkgInfo..."
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Clear extended attributes
echo_status "Clearing extended attributes..."
xattr -cr "$APP_BUNDLE"

# Sign the app
echo_status "Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Register with Launch Services
echo_status "Registering with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE"

# Verify the signature
echo_status "Verifying signature..."
if codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    echo -e "${GREEN}Signature verified successfully${NC}"
else
    echo_warning "Signature verification had warnings (this is normal for ad-hoc signing)"
fi

# Install if requested
if [ "$INSTALL" = true ]; then
    INSTALL_PATH="/Applications/${BUNDLE_NAME}.app"
    echo_status "Installing to /Applications..."

    # Kill any running instance
    pkill -9 "$BUNDLE_NAME" 2>/dev/null || true

    # Remove old installation
    if [ -d "$INSTALL_PATH" ]; then
        rm -rf "$INSTALL_PATH"
    fi

    # Copy to Applications
    cp -R "$APP_BUNDLE" "$INSTALL_PATH"

    # Register the installed app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_PATH"

    echo -e "${GREEN}Installed to $INSTALL_PATH${NC}"
fi

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open \"$APP_BUNDLE\""
echo ""
if [ "$INSTALL" = false ]; then
    echo "To install to /Applications:"
    echo "  $0 --install"
    echo ""
fi
