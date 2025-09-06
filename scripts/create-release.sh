#!/bin/bash

# Web Browser - GitHub Release Creation Script
# Creates a GitHub release with the packaged app
# Author: Tom Cranstoun (ddttom)

set -e  # Exit on any error

# Configuration
REPO_OWNER="ddttom"
REPO_NAME="Web"

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

# Function to get current version from package.json
get_current_version() {
    if [ -f "package.json" ]; then
        node -p "require('./package.json').version" 2>/dev/null || echo "0.0.4"
    else
        echo "0.0.4"
    fi
}

# Function to validate version format
validate_version() {
    local version=$1
    if [[ ! $version =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
        log_error "Invalid version format. Use semantic versioning (e.g., v1.0.0 or 1.0.0)"
        return 1
    fi
    return 0
}

# Function to check if tag exists
tag_exists() {
    local tag=$1
    git tag -l | grep -q "^${tag}$"
}

# Function to create release notes
create_release_notes() {
    local version=$1
    local notes_file="/tmp/release-notes-${version}.md"
    
    cat > "$notes_file" << EOF
# Web Browser ${version}

## 🚀 What's New

- Native macOS AI browser with integrated MLX support
- Local AI processing with Ollama, MLX, and cloud provider support
- Privacy-focused browsing with built-in ad blocking
- Tab hibernation for optimal performance
- Comprehensive keyboard shortcuts

## 📦 Installation

1. Download \`Web-${version}-macOS.zip\` below
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

## 🐛 Known Issues

- First launch may show security warning (see installation guide in ZIP)
- AI model download may take time on first use

## 📝 Installation Guide

The downloaded ZIP contains:
- \`Web.app\` - The main application
- \`INSTALL.md\` - Detailed installation instructions
- \`README.md\` - Quick start guide

For troubleshooting, see the included documentation or visit our [GitHub repository](https://github.com/${REPO_OWNER}/${REPO_NAME}).

---

**Download Size**: ~14.5MB (ZIP) | **Installed Size**: ~61MB
**Supported Platforms**: macOS 14.6+
EOF

    echo "$notes_file"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [version] [options]"
    echo ""
    echo "Arguments:"
    echo "  version     Version to release (e.g., v1.0.0). If not provided, will prompt."
    echo ""
    echo "Options:"
    echo "  --draft     Create as draft release"
    echo "  --prerelease Create as pre-release"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 v1.0.0                    # Create release v1.0.0"
    echo "  $0 v1.0.0-beta --prerelease  # Create pre-release"
    echo "  $0 --draft                   # Create draft with current version"
}

# Parse command line arguments
VERSION=""
DRAFT_FLAG=""
PRERELEASE_FLAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --draft)
            DRAFT_FLAG="--draft"
            shift
            ;;
        --prerelease)
            PRERELEASE_FLAG="--prerelease"
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option $1"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION=$1
            else
                log_error "Multiple versions specified"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting GitHub release creation process..."
    
    # Check prerequisites
    if ! command_exists gh; then
        log_error "GitHub CLI (gh) not found. Install with: brew install gh"
        exit 1
    fi
    
    if ! command_exists git; then
        log_error "Git not found. Please install Git."
        exit 1
    fi
    
    if ! command_exists npm; then
        log_error "npm not found. Please install Node.js."
        exit 1
    fi
    
    # Check if authenticated with GitHub
    if ! gh auth status >/dev/null 2>&1; then
        log_warning "Not authenticated with GitHub. Running authentication..."
        gh auth login
    fi
    
    # Get version if not provided
    if [ -z "$VERSION" ]; then
        local current_version=$(get_current_version)
        echo -n "Enter version to release (current: $current_version): "
        read VERSION
        if [ -z "$VERSION" ]; then
            VERSION="v$current_version"
        fi
    fi
    
    # Ensure version starts with 'v'
    if [[ ! $VERSION =~ ^v ]]; then
        VERSION="v$VERSION"
    fi
    
    # Validate version format
    if ! validate_version "$VERSION"; then
        exit 1
    fi
    
    log_info "Creating release for version: $VERSION"
    
    # Check if tag already exists
    if tag_exists "$VERSION"; then
        log_warning "Tag $VERSION already exists"
        echo -n "Do you want to delete and recreate it? (y/N): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log_info "Deleting existing tag..."
            git tag -d "$VERSION" || true
            git push origin ":refs/tags/$VERSION" || true
        else
            log_error "Aborting release creation"
            exit 1
        fi
    fi
    
    # Ensure we're on the main branch and up to date
    log_info "Checking git status..."
    local current_branch=$(git branch --show-current)
    if [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
        log_warning "Not on main/master branch (currently on: $current_branch)"
        echo -n "Continue anyway? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_error "Aborting release creation"
            exit 1
        fi
    fi
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        log_warning "You have uncommitted changes"
        echo -n "Continue anyway? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_error "Aborting release creation"
            exit 1
        fi
    fi
    
    # Create the package
    log_info "Creating release package..."
    if ! npm run release:package; then
        log_error "Package creation failed"
        exit 1
    fi
    
    # Verify the ZIP file exists
    local zip_file="release/Web-${VERSION}-macOS.zip"
    if [ ! -f "$zip_file" ]; then
        # Check if there's a ZIP file with the current package version
        local package_version=$(get_current_version)
        local package_zip="release/Web-v${package_version}-macOS.zip"
        if [ -f "$package_zip" ]; then
            log_warning "ZIP file found with package version: $package_zip"
            log_info "Renaming to match release version: $zip_file"
            mv "$package_zip" "$zip_file"
        else
            log_error "ZIP file not found: $zip_file"
            log_error "Also checked: $package_zip"
            exit 1
        fi
    fi
    
    local zip_size=$(du -h "$zip_file" | cut -f1)
    log_success "Package created: $zip_file ($zip_size)"
    
    # Create and push tag
    log_info "Creating git tag..."
    git tag -a "$VERSION" -m "Release $VERSION"
    git push origin "$VERSION"
    log_success "Tag $VERSION created and pushed"
    
    # Create release notes
    log_info "Generating release notes..."
    local notes_file=$(create_release_notes "$VERSION")
    
    # Create GitHub release
    log_info "Creating GitHub release..."
    local release_cmd="gh release create $VERSION $zip_file --title \"Web Browser $VERSION\" --notes-file $notes_file $DRAFT_FLAG $PRERELEASE_FLAG"
    
    if eval $release_cmd; then
        log_success "GitHub release created successfully!"
        
        # Clean up
        rm -f "$notes_file"
        
        # Show release URL
        local release_url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/${VERSION}"
        echo ""
        log_info "Release URL: $release_url"
        
        if [ -n "$DRAFT_FLAG" ]; then
            log_warning "Release created as DRAFT. Edit and publish at: $release_url"
        else
            log_success "Release is now live and available for download!"
        fi
        
        # Show download stats command
        echo ""
        log_info "To check download stats later, run:"
        echo "  gh release view $VERSION"
        
    else
        log_error "Failed to create GitHub release"
        # Clean up tag on failure
        git tag -d "$VERSION" || true
        git push origin ":refs/tags/$VERSION" || true
        rm -f "$notes_file"
        exit 1
    fi
}

# Show help if requested
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"