# Web - macOS AI Browser

Built natively with SwiftUI to delivers a minimal, progressive browsing experience with integrated AI capabilities.

<img width="4694" height="2379" alt="image" src="https://github.com/user-attachments/assets/b54a2937-09d5-480a-9ca6-eae7967af30c" />

![Web Browser](https://img.shields.io/badge/platform-macOS-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

*_Note: This is an experimental early access version, as AI models improve so will Web._*

*_Note 2: The AI features require an Apple M chip._* or BYOK to use AI providers like OpenAI, Anthropic and Gemini

*_Note 3: The current version is meant to experiment, play around and give feedback to gear development. It's missing key features as a browser._*

## What's working


https://github.com/user-attachments/assets/e16842f8-fc2a-4984-91ee-9b012bd792f5

NEW: AI Agents and BYOK AI cloud providers (OpenAI, Anthropic, Gemini)

https://github.com/user-attachments/assets/85629abc-5527-4345-b1a8-a988e0417c0a


### Core Browsing
- **WebKit Integration**: Native WebKit rendering with WKWebView
- **Tab Management**: Tab hibernation for optimal performance
- **Keyboard Shortcuts**: Comprehensive shortcuts (⌘T, ⌘W, ⌘R, etc.)
- **Downloads**: Built-in download manager with progress tracking (Need to test)

### Privacy & Security
- **Incognito Mode**: Private browsing sessions
- **Ad Blocking**: Integrated ad blocking service (Need to test if it can be disabled)
- **Password Management**: Secure password handling (Need to test)
- **Privacy Settings**: Granular privacy controls (Need to test)

### AI Integration
- **Local AI Models**: On-device AI powered by [Apple MLX](https://github.com/ml-explore/mlx) and [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- **MLX Framework**: Apple Silicon optimized inference
- **Privacy-First**: AI processing happens locally on device
- **Smart Initialization**: Intelligent startup that recognizes existing downloads and avoids conflicts
- **Manual Download Support**: Seamless coordination with manual download processes
- **Smart Assistance**: Integrated AI sidebar for web content analysis with TL;DR and page + history context. (Still rough with bugs, but nice to play and have fun)

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (for AI features)
- Xcode 15.0+ (for development)
- Node.js 16.0+ (for npm build scripts)

## Installation

### From Source

1. Clone the repository:
```bash
git clone https://github.com/ddttom/AI-Web-Browser.git
cd AI-Web-Browser
```

2. **Option A: Using npm scripts (Recommended)**
```bash
# Build release version
npm run build

# Build debug version
npm run build:debug

# Clean and build
npm run clean:build

# Run tests
npm run test

# Build and run debug version
npm run run
```

3. **Option B: Using Xcode**
```bash
# Open in Xcode
open Web.xcodeproj
# Then build and run (⌘R)
```

4. **Recommended**: Run the manual model download script to avoid AI initialization issues:
   ```bash
   # Standard download (skips if files exist)
   ./scripts/manual_model_download.sh
   
   # Force download (re-downloads all files)
   ./scripts/manual_model_download.sh -f
   
   # Show help
   ./scripts/manual_model_download.sh -h
   ```

5. **Optional**: For advanced users who want to convert GGUF models to MLX format:
   ```bash
   ./scripts/convert_gemma.sh
   ```

## Architecture

Web follows MVVM architecture with SwiftUI and Combine. For detailed architecture documentation, see [Architecture.md](docs/Architecture.md).

```
Web/
├── Models/           # Data models (Tab, Bookmark, etc.)
├── Views/           # SwiftUI views and components
├── ViewModels/      # Business logic and state management
├── Services/        # Core services (Download, History, etc.)
├── AI/             # Local AI integration
└── Utils/          # Utilities and extensions
```

### Key Components

- **TabManager**: Handles tab lifecycle and hibernation
- **WebView**: SwiftUI wrapper around WKWebView
- **MLXRunner**: Local AI model execution
- **DownloadManager**: File download handling
- **BookmarkService**: Bookmark management

## AI Features

Web integrates local AI capabilities using Apple's MLX framework and Swift examples:

- **Framework**: [Apple MLX](https://github.com/ml-explore/mlx) with [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- **Models**: Gemma 2 2B (4-bit quantized) and other compatible models
- **Inference**: MLX-optimized for Apple Silicon
- **Privacy**: All AI processing happens locally
- **Auto-Download**: Models are automatically downloaded on first use
- **Recovery**: Automatic error recovery with manual fallback options

### Model Download Issues

The app now includes **intelligent AI initialization** that coordinates with manual downloads:

**Smart Startup Behavior**:
- **Recognizes Existing Models**: Instantly loads pre-downloaded models without re-downloading
- **Manual Download Coordination**: Detects and waits for active manual download processes
- **Conflict Prevention**: Avoids cache interference during manual downloads
- **Graceful Fallback**: Automatically downloads if no manual process is detected

**Enhanced Manual Download Script**:
```bash
# Standard mode - skips download if files already exist
./scripts/manual_model_download.sh

# Force mode - re-downloads all files regardless of existing files
./scripts/manual_model_download.sh -f

# Help and usage information
./scripts/manual_model_download.sh -h
```

**Model Management Script**:
```bash
# Clear downloaded models (useful for testing/troubleshooting)
./scripts/clear_model.sh
```

**Standalone Model Converter** (for advanced users):
```bash
./scripts/convert_gemma.sh
```

This script converts GGUF Gemma models to MLX format for Apple Silicon optimization. It requires:
- Python 3 with `mlx-lm` package (`pip install mlx-lm`)
- Converts from Hugging Face GGUF models to optimized MLX format
- Outputs to `~/Library/Caches/Web/AI/Models/` directory
- Includes automatic model verification and README generation

**Debug Information**: The manual download script now includes comprehensive debug messages that track:
- Script execution flow and location tracking
- File download progress and verification
- Cache directory operations and cleanup
- Error conditions and recovery attempts
- Process coordination and timing information

**Enhanced Features**:
- **Intelligent Detection**: Recognizes existing valid downloads automatically
- **Process Coordination**: Waits for manual downloads to complete before proceeding
- **Automatic Recovery**: Detects and fixes corrupted downloads automatically
- **Cache Management**: Built-in cache cleanup and validation tools
- **Troubleshooting**: See [docs/Troubleshooting.md](docs/Troubleshooting.md) for detailed recovery steps</search>
</search_and_replace>

### Code Standards

- Swift 6 with strict concurrency
- Zero warnings/errors policy
- Comprehensive keyboard shortcuts
- Memory-efficient tab management

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Troubleshooting

### MLX Model Download Issues

If you encounter AI initialization errors:

1. **Automatic Recovery**: The app will attempt to fix corrupted downloads automatically
2. **Manual Recovery**: If automatic recovery fails, run:
   ```bash
   # Standard recovery (skips if files exist)
   ./scripts/manual_model_download.sh
   
   # Force fresh download (re-downloads all files)
   ./scripts/manual_model_download.sh -f
   ```
3. **Clear Cache**: For complete reset, clear existing models first:
   ```bash
   ./scripts/clear_model.sh
   ./scripts/manual_model_download.sh
   ```
4. **Debug Output**: The enhanced manual download script provides detailed debug messages showing:
   - Script execution progress and current location
   - File download attempts and success/failure status
   - Cache directory creation and cleanup operations
   - Error conditions with specific failure points
   - Process coordination and timing information
   - Force mode operations and file management
5. **Cache Management**: Use Settings > Model Management to view and clean cache
6. **Full Documentation**: See [docs/Troubleshooting.md](docs/Troubleshooting.md) for complete recovery steps

### Common Issues

- **"MLX model tokenizer corrupted"**: Run the manual download script
- **"Automatic recovery failed"**: Clear cache manually and restart app
- **"MLX model validation failed"**: Files downloaded but app can't detect them:
  ```bash
  # Verify files are accessible
  ./scripts/verify_model.sh
  
  # Force fresh download if needed
  ./scripts/manual_model_download.sh -f
  ```
- **Network issues**: Check firewall settings for Hugging Face access
- **Disk space**: Ensure 5GB+ free space for model downloads

### Enhanced Troubleshooting Scripts

**Model Verification Script**:
```bash
./scripts/verify_model.sh
```
This script checks:
- Directory structure and permissions
- File existence and sizes
- File readability and accessibility
- Path consistency between script and app expectations

**Complete Model Management Workflow**:
```bash
# 1. Verify current state
./scripts/verify_model.sh

# 2. Clear if needed
./scripts/clear_model.sh

# 3. Download fresh files
./scripts/manual_model_download.sh -f

# 4. Verify again
./scripts/verify_model.sh

# 5. Start app with enhanced debug logging
```

### Advanced Model Conversion

For users who want to convert GGUF models to MLX format manually:

```bash
# Install required Python package
pip install mlx-lm

# Run the conversion script
./scripts/convert_gemma.sh
```

**Features:**
- Converts GGUF Gemma models from Hugging Face to MLX format
- 4-bit quantization for optimal Apple Silicon performance
- Automatic model verification and validation
- Creates model README with performance estimates
- Outputs to standard Web browser cache directory

## Building the Project

### Quick Start

```bash
# Install dependencies (if using npm scripts)
npm install

# Build release version (recommended)
npm run build

# Build and run debug version
npm run run
```

### Build Scripts

The project includes npm scripts for convenient command-line building:

| Command | Description | Use Case |
|---------|-------------|----------|
| `npm run build` | Build release version | Production builds, distribution |
| `npm run build:debug` | Build debug version | Development, debugging |
| `npm run clean` | Clean build artifacts | Before fresh builds |
| `npm run clean:build` | Clean and build release | Ensure clean release build |
| `npm run clean:all` | Remove all build files and clean | Fix build issues |
| `npm run test` | Run unit tests | Continuous integration |
| `npm run archive` | Create archive for distribution | App Store submission |
| `npm run run` | Build debug and launch app | Quick development cycle |
| `npm run dev` | Alias for debug build | Development workflow |
| `npm run release` | Clean and build release | Final release preparation |
| `npm run kill-builds` | Kill any running xcodebuild processes | Fix concurrent build issues |

### Build Configurations

- **Debug**: Optimized for development with debugging symbols and faster compilation
- **Release**: Optimized for production with full optimizations and smaller binary size
- **Archive**: Creates distributable `.xcarchive` for App Store or direct distribution

### Build Output Locations

- **Debug builds**: `./build/DerivedData/Build/Products/Debug/Web.app`
- **Release builds**: `./build/DerivedData/Build/Products/Release/Web.app`
- **Archives**: `./build/Web.xcarchive`

### Build Dependencies

The build process automatically resolves Swift Package Manager dependencies:
- **MLX Swift**: Apple's machine learning framework
- **Swift Transformers**: Hugging Face transformers for Swift
- **Swift Collections**: Advanced collection types
- **Swift Numerics**: Numerical computing support

### Build Troubleshooting

**Database Locked Error:**
If you encounter "database is locked" errors, it means there are concurrent builds running. To fix this:

1. **Kill existing builds:** `npm run kill-builds`
2. **Clean all build data:** `npm run clean:all`
3. **Try building again:** `npm run build`

**Build Location:**
All builds now use a local `./build/DerivedData` directory to avoid conflicts with Xcode's shared derived data location.

**Common Build Issues:**
- **Swift Package resolution fails**: Run `npm run clean:all` and try again
- **Metal shader compilation errors**: Ensure you're on Apple Silicon Mac
- **Memory issues during build**: Close other applications and try `npm run build` (release builds use less memory)

### CI/CD Integration

For continuous integration, use:
```bash
# Clean build for CI
npm run clean:all && npm run build

# Run tests
npm run test

# Create archive for distribution
npm run archive
```

## Keyboard Shortcuts

| Action | Shortcut | Description |
|--------|----------|-------------|
| New Tab | ⌘T | Open new tab |
| Close Tab | ⌘W | Close current tab |
| Reopen Tab | ⇧⌘T | Reopen last closed tab |
| Reload | ⌘R | Reload current page |
| Address Bar | ⌘L | Focus address bar |
| Find in Page | ⌘F | Search in page |
| Downloads | ⇧⌘J | Show downloads |
| Developer Tools | ⌥⌘I | Open developer tools |
| Toggle Top Bar | ⇧⌘H | Cycle top bar modes |
| Toggle Sidebar | ⌘S | Sidebar vs Top tabs |
| Open AI Panel | ⇧⌘A | Open AI Sidebar |

## Dependencies

- [Apple MLX](https://github.com/ml-explore/mlx) - Machine learning framework for Apple Silicon
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples) - Swift examples and utilities for MLX
- WebKit - Apple's web rendering engine
- Core Data - Local data persistence
- Combine - Reactive programming framework

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Apple MLX](https://github.com/ml-explore/mlx) by Apple for optimized machine learning on Apple Silicon
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples) by Apple for Swift integration examples
- Apple's WebKit team for the excellent web rendering engine
- The Swift community for SwiftUI and modern iOS/macOS development patterns

## 🔗 Links

- Website: [Nuanc.me](https://nuanc.me)
- Report issues: [GitHub Issues](https://github.com/ddttom/AI-Web-Browser/issues)
- Follow updates: [@Nuanced](https://x.com/Nuancedev)
- [Buy me a coffee](https://buymeacoffee.com/nuanced)
