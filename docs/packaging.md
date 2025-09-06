# Release Packaging Guide

This document describes the automated release packaging system for creating distributable .app bundles of the Web browser.

## Overview

The Web browser includes a comprehensive release packaging system that creates professional distribution packages ready for end-user installation. The system handles building, validation, documentation generation, and archive creation automatically.

## Quick Start

```bash
# Create a complete distribution package
npm run release:package
```

This single command handles the entire packaging process and creates both a distribution folder and compressed archive.

## Packaging Process

### 1. Build Validation
- Verifies Xcode and npm are available
- Checks system requirements
- Validates project structure

### 2. Clean Build
- Removes previous build artifacts
- Performs a fresh release build
- Ensures no development artifacts are included

### 3. App Bundle Validation
The system performs comprehensive validation of the built app:

- **Bundle Structure**: Verifies proper .app bundle organization
- **Executable**: Confirms the main executable exists and is valid Mach-O binary
- **Info.plist**: Validates property list structure and required keys
- **Code Signing**: Ensures proper code signing is applied
- **Resources**: Verifies all required resources are included

### 4. Distribution Package Creation
Creates a complete distribution folder with:

#### Core Application
- `Web.app` - Complete 61MB application bundle with all dependencies

#### Documentation
- `INSTALL.md` - Comprehensive installation guide including:
  - System requirements
  - Step-by-step installation instructions
  - Security guidance for first launch
  - AI features setup
  - Troubleshooting information
- `README.md` - Distribution overview and quick start
- `LICENSE` - Software license
- `VERSION.txt` - Build metadata including version, date, and git commit

### 5. Archive Creation
- Creates compressed ZIP archive for distribution
- Optimized for download and sharing
- Maintains proper file permissions and structure

## Output Structure

```
release/
├── Web-Distribution/                    # Distribution folder
│   ├── Web.app/                        # Application bundle (61MB)
│   │   ├── Contents/
│   │   │   ├── MacOS/Web              # Main executable (57MB)
│   │   │   ├── Resources/             # App resources (3.6MB)
│   │   │   ├── Info.plist             # Bundle configuration
│   │   │   └── _CodeSignature/        # Code signing data
│   │   └── ...
│   ├── INSTALL.md                      # Installation instructions
│   ├── README.md                       # Distribution overview
│   ├── LICENSE                         # Software license
│   └── VERSION.txt                     # Version information
└── Web-v[version]-macOS.zip            # Compressed archive (14.5MB)
```

## App Bundle Contents

The packaged app includes all necessary components:

### Core Application (57MB)
- Swift executable with all frameworks
- MLX machine learning libraries
- WebKit integration
- AI processing capabilities

### Resources (3.6MB)
- **MLX Bundle** (2.8MB): Metal shaders and ML model support
- **Transformers Bundle** (32KB): AI tokenizer configurations
- **Assets** (800KB): Icons, images, and UI resources
- **Configuration**: JavaScript files and settings

### Code Signing
- Proper macOS code signing applied
- Enables distribution outside App Store
- Reduces security warnings for users

## Distribution Methods

### GitHub Releases (Recommended)

**Quick Release (for existing packages):**
```bash
npm run release:quick
```
- Uses existing ZIP file
- Creates Git tag and GitHub release
- Immediate public availability

**Full Release (build + release):**
```bash
npm run release:github v1.0.0
```
- Builds fresh package
- Creates complete GitHub release
- Professional release notes

### Direct Distribution
1. Share the ZIP file with users
2. Users download and extract
3. Drag Web.app to Applications folder
4. Launch from Applications or Spotlight

### Website Distribution
1. Host ZIP file on web server
2. Provide download link
3. Include installation instructions

## Validation and Testing

The packaging system includes built-in validation:

### Automated Checks
- App bundle structure validation
- Executable verification (Mach-O format)
- Info.plist syntax and content validation
- Code signing verification
- Resource completeness check

### Manual Testing
After packaging, test the distribution:

```bash
# Test the packaged app
open release/Web-Distribution/Web.app

# Verify app launches successfully
# Check AI features work correctly
# Test browser functionality
```

## Troubleshooting

### Common Issues

**Build Fails**
- Ensure Xcode command line tools are installed
- Check that all dependencies are available
- Verify sufficient disk space (>5GB recommended)

**App Won't Launch**
- Check code signing status
- Verify all frameworks are included
- Test on clean macOS system

**Large File Size**
- The 61MB size includes all ML frameworks
- MLX and Swift frameworks contribute most of the size
- This is expected for a full-featured AI browser

### Debug Information

The packaging script provides detailed logging:
- Build progress and status
- Validation results
- File sizes and locations
- Error messages with context

### Getting Help

For packaging issues:
1. Check the build logs for specific errors
2. Verify system requirements are met
3. Try a clean build: `npm run clean:all && npm run release:package`
4. Report issues at: https://github.com/ddttom/Web/issues

## Advanced Configuration

### Customizing the Package

The packaging script can be customized by modifying [`scripts/build-release.sh`](../scripts/build-release.sh):

- Change distribution folder structure
- Modify documentation templates
- Add additional validation steps
- Customize archive naming

### Build Environment

For consistent packaging:
- Use macOS 14.6 or later
- Xcode 15.0 or later
- Node.js 16.0 or later
- Sufficient disk space (5GB+)

## Security Considerations

### Code Signing
- The app is code signed for distribution
- Uses development certificate (suitable for direct distribution)
- For App Store distribution, additional steps required

### Privacy
- No telemetry or tracking in packaged app
- AI processing happens locally by default
- User data remains on device

### Updates
- Manual update process (download new version)
- Future versions may include auto-update capability
- Users should download from trusted sources only

## Performance

### Package Sizes
- **Uncompressed**: 61MB app bundle
- **Compressed**: 14.5MB ZIP archive
- **Download time**: ~30 seconds on typical broadband

### Installation Time
- **Extract**: ~5 seconds
- **Copy to Applications**: ~10 seconds
- **First launch**: ~15 seconds (AI model initialization)

## Future Enhancements

Planned improvements to the packaging system:
- Notarization support for enhanced security
- DMG creation for professional installer experience
- Automated GitHub release integration
- Delta updates for smaller download sizes