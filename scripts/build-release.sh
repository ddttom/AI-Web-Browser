#!/bin/bash

# Web Browser - Release Build Script
# Creates a distributable .app bundle for macOS
# Author: Tom Cranstoun (ddttom)

set -e  # Exit on any error

# Configuration
APP_NAME="Web"
BUILD_DIR="./build"
RELEASE_DIR="./release"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
APP_BUNDLE_PATH="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"
DISTRIBUTION_DIR="$RELEASE_DIR/$APP_NAME-Distribution"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get app version from Info.plist
get_app_version() {
    if [ -f "$APP_BUNDLE_PATH/Contents/Info.plist" ]; then
        /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_BUNDLE_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0.0"
    else
        echo "1.0.0"
    fi
}

# Function to validate app bundle
validate_app_bundle() {
    log_info "Validating app bundle..."
    
    # Check if app bundle exists
    if [ ! -d "$APP_BUNDLE_PATH" ]; then
        log_error "App bundle not found at $APP_BUNDLE_PATH"
        return 1
    fi
    
    # Check if executable exists
    if [ ! -f "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME" ]; then
        log_error "Executable not found in app bundle"
        return 1
    fi
    
    # Check if executable is valid
    if ! file "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME" | grep -q "Mach-O"; then
        log_error "Executable is not a valid Mach-O binary"
        return 1
    fi
    
    # Check Info.plist
    if [ ! -f "$APP_BUNDLE_PATH/Contents/Info.plist" ]; then
        log_error "Info.plist not found in app bundle"
        return 1
    fi
    
    # Validate Info.plist
    if ! plutil -lint "$APP_BUNDLE_PATH/Contents/Info.plist" >/dev/null 2>&1; then
        log_error "Info.plist is not valid"
        return 1
    fi
    
    log_success "App bundle validation passed"
    return 0
}

# Function to create distribution package
create_distribution_package() {
    local version=$(get_app_version)
    log_info "Creating distribution package for version $version..."
    
    # Clean and create release directory
    rm -rf "$RELEASE_DIR"
    mkdir -p "$DISTRIBUTION_DIR"
    
    # Copy app bundle
    log_info "Copying app bundle..."
    cp -R "$APP_BUNDLE_PATH" "$DISTRIBUTION_DIR/"
    
    # Create installation instructions
    log_info "Creating installation instructions..."
    cat > "$DISTRIBUTION_DIR/INSTALL.md" << EOF
# Web Browser Installation

## System Requirements
- macOS 14.6 or later
- Apple Silicon (M1/M2/M3) or Intel Mac

## Installation Instructions

### Method 1: Drag and Drop (Recommended)
1. Open this folder and your Applications folder side by side
2. Drag the **Web.app** to your Applications folder
3. Launch Web from Applications or Spotlight

### Method 2: Terminal Installation
\`\`\`bash
# Copy to Applications folder
cp -R "Web.app" "/Applications/"

# Launch the application
open "/Applications/Web.app"
\`\`\`

## First Launch
- The app may show a security warning on first launch
- Go to System Preferences > Security & Privacy > General
- Click "Open Anyway" next to the Web app warning
- Or right-click the app and select "Open" from the context menu

## AI Features Setup
The browser includes local AI capabilities:
- **Ollama**: Install from https://ollama.ai for instant AI (recommended)
- **MLX**: Works automatically on Apple Silicon Macs
- **Cloud APIs**: Configure your own API keys in Settings

## Troubleshooting
- If the app won't open, check System Preferences > Security & Privacy
- For AI model issues, see the included documentation
- Report issues at: https://github.com/ddttom/Web/issues

## Version Information
- Version: $version
- Build Date: $(date)
- Platform: macOS (Universal)
EOF

    # Create README for distribution
    log_info "Creating distribution README..."
    cat > "$DISTRIBUTION_DIR/README.md" << EOF
# Web - AI-Powered macOS Browser

A native macOS browser built with SwiftUI, featuring integrated AI capabilities and privacy-focused design.

## What's Included
- **Web.app** - The main application
- **INSTALL.md** - Installation instructions
- **LICENSE** - Software license

## Key Features
- Native WebKit rendering with SwiftUI
- Local AI integration (MLX, Ollama)
- Privacy-focused browsing
- Tab hibernation for performance
- Built-in ad blocking
- Comprehensive keyboard shortcuts

## Quick Start
1. Drag Web.app to your Applications folder
2. Launch and enjoy browsing with AI assistance
3. Configure AI providers in Settings if desired

For detailed setup and usage instructions, see INSTALL.md

---
Built by Tom Cranstoun (ddttom) | Version $version
EOF

    # Copy license if it exists
    if [ -f "LICENSE" ]; then
        cp "LICENSE" "$DISTRIBUTION_DIR/"
    fi
    
    # Create version info file
    cat > "$DISTRIBUTION_DIR/VERSION.txt" << EOF
Web Browser v$version
Build Date: $(date)
Build Host: $(hostname)
Git Commit: $(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
Xcode Version: $(xcodebuild -version | head -1 2>/dev/null || echo "unknown")
EOF

    log_success "Distribution package created at $DISTRIBUTION_DIR"
}

# Function to create ZIP archive
create_zip_archive() {
    local version=$(get_app_version)
    local zip_name="$RELEASE_DIR/Web-v$version-macOS.zip"
    
    log_info "Creating ZIP archive..."
    
    cd "$RELEASE_DIR"
    zip -r "Web-v$version-macOS.zip" "$APP_NAME-Distribution/" -x "*.DS_Store"
    cd - >/dev/null
    
    local zip_size=$(du -h "$zip_name" | cut -f1)
    log_success "ZIP archive created: $zip_name ($zip_size)"
}

# Main execution
main() {
    log_info "Starting Web Browser release build process..."
    
    # Check prerequisites
    if ! command_exists xcodebuild; then
        log_error "Xcode command line tools not found. Please install Xcode."
        exit 1
    fi
    
    if ! command_exists npm; then
        log_error "npm not found. Please install Node.js."
        exit 1
    fi
    
    # Clean previous builds
    log_info "Cleaning previous builds..."
    npm run clean >/dev/null 2>&1 || true
    
    # Build the application
    log_info "Building release version..."
    if ! npm run build; then
        log_error "Build failed"
        exit 1
    fi
    
    # Validate the build
    if ! validate_app_bundle; then
        log_error "App bundle validation failed"
        exit 1
    fi
    
    # Create distribution package
    create_distribution_package
    
    # Create ZIP archive
    create_zip_archive
    
    # Final summary
    local version=$(get_app_version)
    local app_size=$(du -h "$APP_BUNDLE_PATH" | cut -f1)
    
    echo
    log_success "Release build completed successfully!"
    echo
    echo "📦 Distribution Package: $DISTRIBUTION_DIR"
    echo "🗜️  ZIP Archive: $RELEASE_DIR/Web-v$version-macOS.zip"
    echo "📱 App Size: $app_size"
    echo "🏷️  Version: $version"
    echo
    log_info "Ready for distribution!"
}

# Run main function
main "$@"