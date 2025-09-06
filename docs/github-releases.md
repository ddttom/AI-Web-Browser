# GitHub Releases Guide

This guide explains how to create GitHub releases for distributing your Web browser app.

## Overview

GitHub Releases allow you to:
- Distribute your packaged app to users
- Provide release notes and changelogs
- Track download statistics
- Maintain version history
- Enable automatic update notifications

## Quick Start

### Method 1: Quick Release (Easiest - for existing packages)

If you already have a built package (like after running `npm run release:package`):

```bash
npm run release:quick
```

This automatically:
- Detects your existing ZIP file (e.g., `Web-v0.0.4-macOS.zip`)
- Creates and pushes a Git tag
- Generates professional release notes
- Uploads to GitHub releases
- Makes it immediately available for download

### Method 2: Manual Release (Recommended for first-time setup)</search>
</search_and_replace>

1. **Create the package**:
   ```bash
   npm run release:package
   ```

2. **Create a Git tag**:
   ```bash
   # Tag the current commit with version number
   git tag v0.0.4
   git push origin v0.0.4
   ```

3. **Create GitHub Release**:
   - Go to your repository on GitHub
   - Click "Releases" in the right sidebar
   - Click "Create a new release"
   - Select the tag you just created (v0.0.4)
   - Fill in release information:
     - **Release title**: `Web Browser v0.0.4`
     - **Description**: Add release notes (see template below)
   - **Upload the ZIP file**: Drag `release/Web-v0.0.4-macOS.zip` to the assets area
   - Click "Publish release"

### Method 2: Automated Release (Advanced)

Use the GitHub CLI for automated releases:

```bash
# Install GitHub CLI if not already installed
brew install gh

# Authenticate with GitHub
gh auth login

# Create release with package
npm run release:package
gh release create v0.0.4 release/Web-v0.0.4-macOS.zip \
  --title "Web Browser v0.0.4" \
  --notes-file CHANGELOG.md
```

## Release Notes Template

Create compelling release notes using this template:

```markdown
# Web Browser v0.0.4

## 🚀 What's New

- Native macOS AI browser with integrated MLX support
- Local AI processing with Ollama, MLX, and cloud provider support
- Privacy-focused browsing with built-in ad blocking
- Tab hibernation for optimal performance
- Comprehensive keyboard shortcuts

## 📦 Installation

1. Download `Web-v0.0.4-macOS.zip` below
2. Unzip the archive
3. Drag `Web.app` to your Applications folder
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

- First launch may show security warning (see installation guide)
- AI model download may take time on first use

## 📝 Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for complete changes.

---

**Download**: Web-v0.0.4-macOS.zip (14.5MB)
**App Size**: 61MB when installed
**Supported**: macOS 14.6+
```

## Automated Release Script

Create a script to automate the entire release process:

```bash
#!/bin/bash
# scripts/create-release.sh

set -e

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.0.5"
    exit 1
fi

echo "Creating release $VERSION..."

# 1. Create package
echo "📦 Creating package..."
npm run release:package

# 2. Create and push tag
echo "🏷️ Creating git tag..."
git tag $VERSION
git push origin $VERSION

# 3. Create GitHub release
echo "🚀 Creating GitHub release..."
gh release create $VERSION release/Web-$VERSION-macOS.zip \
  --title "Web Browser $VERSION" \
  --notes "Release $VERSION of Web Browser. See CHANGELOG.md for details." \
  --draft

echo "✅ Release created successfully!"
echo "📝 Edit the release notes at: https://github.com/ddttom/Web/releases/tag/$VERSION"
```

## Version Management

### Semantic Versioning

Use semantic versioning (semver) for your releases:
- `v1.0.0` - Major release (breaking changes)
- `v0.1.0` - Minor release (new features)
- `v0.0.1` - Patch release (bug fixes)

### Updating Version Numbers

Update version in multiple places:

1. **package.json**:
   ```json
   {
     "version": "0.0.5"
   }
   ```

2. **Xcode project** (if using marketing version):
   - Open Web.xcodeproj
   - Select project settings
   - Update "Marketing Version"

3. **Create consistent tags**:
   ```bash
   git tag v0.0.5
   ```

## Release Checklist

Before creating a release:

- [ ] Update version numbers in package.json
- [ ] Update CHANGELOG.md with new features and fixes
- [ ] Test the app thoroughly
- [ ] Run `npm run release:package` successfully
- [ ] Verify the ZIP file works on a clean system
- [ ] Create git tag with version number
- [ ] Write compelling release notes
- [ ] Upload ZIP file to GitHub release
- [ ] Test download and installation process

## Best Practices

### Release Frequency
- **Major releases**: Every 3-6 months
- **Minor releases**: Monthly for new features
- **Patch releases**: As needed for critical fixes

### Release Notes
- Use clear, user-friendly language
- Highlight new features prominently
- Include installation instructions
- Mention system requirements
- List known issues honestly

### Asset Management
- Always include the ZIP file as the primary asset
- Use consistent naming: `Web-v[version]-macOS.zip`
- Include checksums for security (optional)
- Keep old releases available for compatibility

### Communication
- Announce releases on social media
- Update documentation links
- Notify beta testers
- Consider release notifications in the app

## Troubleshooting

### Common Issues

**Tag already exists**:
```bash
# Delete local and remote tag
git tag -d v0.0.4
git push origin :refs/tags/v0.0.4
# Then recreate
```

**Release upload fails**:
- Check file size limits (2GB max)
- Verify file permissions
- Ensure stable internet connection

**GitHub CLI authentication**:
```bash
gh auth status
gh auth login --web
```

### Getting Help

For GitHub releases issues:
1. Check GitHub's release documentation
2. Verify repository permissions
3. Test with GitHub CLI: `gh release list`
4. Contact GitHub support if needed

## Advanced Features

### Pre-releases
For beta versions:
```bash
gh release create v0.0.5-beta release/Web-v0.0.5-beta-macOS.zip \
  --title "Web Browser v0.0.5 Beta" \
  --prerelease
```

### Release Assets
Include multiple assets:
- Main ZIP file
- Checksums file
- Release notes PDF
- Screenshots

### Automated Workflows
Consider GitHub Actions for:
- Automated building on tag push
- Release creation
- Asset upload
- Notification sending

## Security Considerations

### Code Signing
- Ensure app is properly code signed
- Consider notarization for enhanced trust
- Include security information in release notes

### Distribution
- Only distribute through official channels
- Provide checksums for verification
- Monitor for unofficial redistributions

### Updates
- Plan for future auto-update mechanism
- Consider security update process
- Maintain backward compatibility when possible