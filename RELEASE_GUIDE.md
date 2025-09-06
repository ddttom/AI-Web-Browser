# Quick Release Guide

This is a step-by-step guide to create your first GitHub release for the Web browser.

## Prerequisites (One-time setup)

1. **Install GitHub CLI**:
   ```bash
   brew install gh
   ```

2. **Authenticate with GitHub**:
   ```bash
   gh auth login
   ```
   Follow the prompts to authenticate with your GitHub account.

## Creating Your First Release

### Option 1: Quick Release (Easiest)

If you already have a package built (like your current v0.0.4):

```bash
# Create GitHub release from existing package
npm run release:quick
```

This will:
- ✅ Use your existing ZIP file
- ✅ Create a Git tag
- ✅ Generate release notes
- ✅ Upload to GitHub releases
- ✅ Make it available for download

### Option 2: Full Automated Release

```bash
# Create a release (will prompt for version)
npm run release:github

# Or specify version directly
npm run release:github v0.0.5
```

The script will:
- ✅ Build and package your app
- ✅ Create a Git tag
- ✅ Generate release notes
- ✅ Upload to GitHub releases
- ✅ Make it available for download

### Option 2: Manual Process

If you prefer to do it manually:

1. **Create the package**:
   ```bash
   npm run release:package
   ```

2. **Create and push a Git tag**:
   ```bash
   git tag v0.0.5
   git push origin v0.0.5
   ```

3. **Create GitHub release**:
   - Go to https://github.com/ddttom/Web/releases
   - Click "Create a new release"
   - Select tag `v0.0.5`
   - Title: `Web Browser v0.0.5`
   - Upload `release/Web-v0.0.5-macOS.zip`
   - Add release notes (see template below)
   - Click "Publish release"

## Release Notes Template

```markdown
# Web Browser v0.0.5

## 🚀 What's New

- Native macOS AI browser with integrated MLX support
- Local AI processing with Ollama, MLX, and cloud provider support
- Privacy-focused browsing with built-in ad blocking
- Tab hibernation for optimal performance

## 📦 Installation

1. Download `Web-v0.0.5-macOS.zip` below
2. Unzip the archive
3. Drag `Web.app` to your Applications folder
4. Launch from Applications or Spotlight

## 🔧 System Requirements

- macOS 14.6 or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- 100MB free disk space

## 🤖 AI Features

- **Ollama**: Install from https://ollama.ai for instant AI
- **MLX**: Works automatically on Apple Silicon Macs
- **Cloud APIs**: Configure your own API keys in Settings

For installation help, see the included `INSTALL.md` file in the download.
```

## Verification

After creating the release:

1. **Check the release page**: https://github.com/ddttom/Web/releases
2. **Test the download**: Download and install on a clean system
3. **Verify the app works**: Launch and test basic functionality

## Next Steps

- Share the release link with users
- Announce on social media
- Update any documentation that references download links
- Monitor download statistics with: `gh release view v0.0.5`

## Troubleshooting

**GitHub CLI not authenticated**:
```bash
gh auth status
gh auth login --web
```

**Tag already exists**:
```bash
git tag -d v0.0.5
git push origin :refs/tags/v0.0.5
```

**Release creation fails**:
- Check internet connection
- Verify GitHub permissions
- Ensure ZIP file exists and is under 2GB

For more detailed information, see [docs/github-releases.md](docs/github-releases.md).