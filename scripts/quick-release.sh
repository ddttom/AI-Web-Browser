#!/bin/bash

# Quick GitHub Release Script
# Uses existing package to create GitHub release
# Author: Tom Cranstoun (ddttom)

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if GitHub CLI is available
if ! command -v gh >/dev/null 2>&1; then
    log_error "GitHub CLI not found. Install with: brew install gh"
    exit 1
fi

# Check authentication
if ! gh auth status >/dev/null 2>&1; then
    log_info "Authenticating with GitHub..."
    gh auth login
fi

# Get version from existing ZIP file
VERSION=""
if [ -f "release/Web-v0.0.4-macOS.zip" ]; then
    VERSION="v0.0.4"
    ZIP_FILE="release/Web-v0.0.4-macOS.zip"
elif [ -f "release/Web-v0.0.5-macOS.zip" ]; then
    VERSION="v0.0.5"
    ZIP_FILE="release/Web-v0.0.5-macOS.zip"
else
    log_error "No release ZIP file found. Run 'npm run release:package' first."
    exit 1
fi

log_info "Found package: $ZIP_FILE"
log_info "Creating GitHub release for version: $VERSION"

# Check if tag exists
if git tag -l | grep -q "^${VERSION}$"; then
    log_info "Tag $VERSION already exists, using existing tag"
else
    log_info "Creating tag $VERSION"
    git tag -a "$VERSION" -m "Release $VERSION"
    git push origin "$VERSION"
fi

# Create release notes
NOTES="# Web Browser $VERSION

## 🚀 What's New

- Native macOS AI browser with integrated MLX support
- Local AI processing with Ollama, MLX, and cloud provider support
- Privacy-focused browsing with built-in ad blocking
- Tab hibernation for optimal performance
- Comprehensive keyboard shortcuts

## 📦 Installation

1. Download \`Web-$VERSION-macOS.zip\` below
2. Unzip the archive
3. Drag \`Web.app\` to your Applications folder
4. Launch from Applications or Spotlight

## 🔧 System Requirements

- macOS 14.6 or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- 100MB free disk space

## 🤖 AI Features

- **Ollama**: Install from https://ollama.ai for instant AI (recommended)
- **MLX**: Works automatically on Apple Silicon Macs
- **Cloud APIs**: Configure your own API keys in Settings

## 📝 Installation Guide

The downloaded ZIP contains:
- \`Web.app\` - The main application
- \`INSTALL.md\` - Detailed installation instructions
- \`README.md\` - Quick start guide

For troubleshooting, see the included documentation.

---

**Download Size**: ~15MB (ZIP) | **Installed Size**: ~61MB
**Supported Platforms**: macOS 14.6+"

# Create the release
log_info "Creating GitHub release..."
if gh release create "$VERSION" "$ZIP_FILE" \
    --title "Web Browser $VERSION" \
    --notes "$NOTES"; then
    
    log_success "GitHub release created successfully!"
    log_info "Release URL: https://github.com/ddttom/Web/releases/tag/$VERSION"
    log_success "Your app is now available for public download!"
else
    log_error "Failed to create GitHub release"
    exit 1
fi