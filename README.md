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
- **Performance Optimized**: Clean production startup with essential-only logging, optimized auto-read thresholds, debounced AI readiness checks, reduced log noise, and comprehensive debug mode for development
- **Swift 6 Compliant**: Full concurrency support with proper MainActor isolation and Sendable compliance
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

## Development & Debugging

### Logging Configuration

The application uses intelligent logging that adapts to build configuration:

#### Production Builds (Release) - v2.11.0
- **Clean Startup**: Only essential status messages shown - emojis and debug tags automatically removed
- **Minimal Output**: Core functionality updates without verbose details or repetitive logging
- **Enhanced Filtering**: Comprehensive system-level error suppression (WebKit, Metal, network warnings)
- **Optimized Performance**: Throttled guard messages and duplicate initialization prevention
- **Professional Experience**: Clean logs suitable for end users

```
AI model initialization started
AI model found - loading existing files  
AI model ready
AI Assistant initialization complete
```

#### Development Builds (Debug)
- **Comprehensive Logging**: Full debug information available
- **Performance Tracking**: Detailed startup and cache performance metrics  
- **Troubleshooting**: Extensive diagnostic information

```bash
# Enable verbose logging in debug builds
defaults write com.example.Web App.VerboseLogs -bool YES

# Disable verbose logging  
defaults write com.example.Web App.VerboseLogs -bool NO
```

#### Debug Log Categories
- `🚀 [SMART INIT]`: AI model initialization flow and state transitions
- `🔍 [CACHE DEBUG]`: File system cache operations and validation
- `🚀 [MLX RUNNER]`: Model loading and execution with container status
- `📡 [ASYNC NOTIFY]`: Async coordination events and notification system
- `⚡ [SINGLETON]`: Service initialization tracking and lifecycle management
- `🔍 [INIT STATE]`: Detailed state tracking during initialization (v2.10.0)
- `🔍 [AI READY CHECK]`: Readiness check analysis with reasoning (v2.10.0)
- `🔍 [GUARD]`: Coordination logic execution and waiting behavior with throttled logging (v2.11.0)

#### Race Condition Debugging (v2.10.0)
Enhanced debug logging now includes comprehensive state tracking to identify and resolve initialization race conditions:

```bash
# Example debug output showing race condition resolution
🔍 [AI READY CHECK] Smart init in progress: true
🛡️ [GUARD] Waiting for concurrent initialization to complete  
🔍 [GUARD] Smart init completed. Final state: isModelReady=true, downloadState=ready
🔥 [INIT AI] MLX AI model now ready after waiting for smart init
```

This prevents false "download needed" messages when model files already exist.

#### Logging Optimizations (v2.11.0)
Enhanced logging system to reduce noise and improve production experience:

**Production Build Improvements**:
- **Message Cleaning**: Automatic removal of emojis and debug tags in release builds
- **System Error Filtering**: Suppression of benign WebKit, Metal, and network warnings
- **Duplicate Prevention**: Guard against multiple initialization attempts causing log spam

**Debug Build Enhancements**:
- **Throttled Logging**: Guard wait messages reduced from every 0.2s to every 1s interval
- **Full Formatting**: Preserves all emojis and debug markers for development visibility
- **Verbose Control**: Fine-grained control via `App.VerboseLogs` UserDefault

```bash
# Reduced logging frequency example (debug builds)
🔍 [GUARD] Waiting for smart init... current state: isModelReady=false (every 1s vs 0.2s)
```

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

The script now includes:
- **Intelligent Skip Logic**: Automatically detects existing valid downloads
- **Force Download Option**: `-f` flag forces fresh download even if files exist
- **Enhanced Process Detection**: Uses reliable `pgrep` for detecting concurrent downloads
- **Comprehensive Logging**: Detailed debug messages with timestamps and status tracking
- **Lock File Management**: Prevents concurrent download conflicts
- **Progress Validation**: Verifies download integrity before completion

**Model Management Scripts**:
```bash
# Clear downloaded models (enhanced with safety features)
./scripts/clear_model.sh

# Verify model files and accessibility (new diagnostic tool)
./scripts/verify_model.sh
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
- **File Detection Fixes**: Resolved critical model ID mapping inconsistencies between manual downloads and app validation
- **MLX Validation Pipeline**: Enhanced coordination between file detection and MLX model loading
- **Troubleshooting**: See [docs/Troubleshooting.md](docs/Troubleshooting.md) for detailed recovery steps

### Recent Fixes (v2.7.0)

**Swift 6 Concurrency & Performance Optimizations:**
- ✅ **Main Actor Isolation**: Fixed `OAuthManager` timer callback to properly handle main actor isolation with async task coordination
- ✅ **Sendable Compliance**: Resolved WebView capture warnings by properly structuring capture lists for non-sendable types
- ✅ **Conditional Cast Optimization**: Eliminated unnecessary type casting in error handling code
- ✅ **Performance Validation**: Added comprehensive test suite to validate singleton patterns and async coordination
- ✅ **Zero Warnings Policy**: Achieved full Swift 6 compliance with proper concurrency handling

**Enhanced Model Detection & Smart Initialization (v2.6.0):**
- ✅ **Model ID Mapping Fixes**: Resolved critical inconsistencies between manual downloads (`models--mlx-community--gemma-2-2b-it-4bit`) and app validation
- ✅ **Improved File Detection**: Enhanced `findModelDirectory()` with proper Hugging Face cache structure validation (`snapshots/main/` directory)
- ✅ **Smart Download Coordination**: Enhanced manual download detection with detailed debug logs and reliable process checking using `pgrep`
- ✅ **MLX Validation Pipeline**: Fixed coordination to use consistent model ID formats throughout the loading process
- ✅ **SimplifiedMLXRunner**: Added comprehensive error handling supporting both internal and Hugging Face repository formats

**Advanced Smart Initialization Features:**
- **Process Detection**: Intelligent detection of active manual download processes with timeout handling
- **Cache Coordination**: Prevents conflicts between automatic and manual download processes
- **Enhanced Logging**: Comprehensive debug messages with `🔍 [CACHE DEBUG]`, `🚀 [SMART INIT]`, and `🚀 [MLX RUNNER]` prefixes
- **File Validation**: Proper snapshot directory validation to avoid loading incomplete downloads
- **Error Categorization**: Distinguishes between file corruption, missing files, and validation failures

**New Troubleshooting Tools:**
- **Model Verification Script** (`verify_model.sh`): Comprehensive model file validation and accessibility checking
- **Enhanced Clear Script** (`clear_model.sh`): Improved model cache cleanup with detailed file information and confirmation
- **Standalone Converter** (`convert_gemma.sh`): GGUF to MLX format conversion for advanced users

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

**Model Verification Script** (NEW):
```bash
./scripts/verify_model.sh
```
This script provides comprehensive validation:
- Directory structure and permissions verification
- File existence, sizes, and accessibility checking
- Path consistency validation between scripts and app expectations
- Detailed debug output with timestamps and status information

**Enhanced Model Clearing Script**:
```bash
./scripts/clear_model.sh
```
Improved features:
- Shows detailed file information before deletion (sizes, counts)
- Calculates total space to be freed
- Provides confirmation prompts for safety
- Removes lock files and incomplete downloads
- Cleans up empty directories automatically

**Complete Model Management Workflow**:
```bash
# 1. Verify current model state
./scripts/verify_model.sh

# 2. Clear corrupted models if needed
./scripts/clear_model.sh

# 3. Download fresh files (force mode ensures clean download)
./scripts/manual_model_download.sh -f

# 4. Verify successful download
./scripts/verify_model.sh

# 5. Start app - should now detect models correctly
```

**Advanced: Standalone Model Conversion**:
```bash
./scripts/convert_gemma.sh
```
For users wanting to convert GGUF models to MLX format:
- Converts from Hugging Face GGUF models to optimized MLX format
- Includes 4-bit quantization for Apple Silicon optimization
- Automatic model verification and README generation
- Outputs to standard Web browser cache directory

## Performance Optimizations

Web includes comprehensive performance optimizations for efficient AI initialization and resource management:

### Async/Await AI Initialization

**Problem**: Previous versions used polling-based AI readiness checks causing excessive CPU usage and startup delays.

**Solution**: Implemented async/await pattern with `withCheckedContinuation` for efficient AI readiness coordination:

```swift
// Efficient async waiting instead of polling
let isReady = await mlxModelService.waitForAIReadiness()
if isReady {
    AppLog.debug("✅ AI readiness wait completed successfully")  
} else {
    AppLog.error("❌ AI readiness wait failed")
}
```

**Benefits**:
- **Zero CPU overhead**: No polling loops consuming resources
- **Immediate response**: Notification-based wakeup when AI becomes ready
- **Multiple waiters**: Supports concurrent async waiters with single notification
- **Comprehensive logging**: Success/failure tracking for debugging

### Singleton Pattern Implementation

**Services optimized with singleton pattern**:
- `MLXModelService.shared`: Prevents multiple model service instances
- `AIAssistant.shared`: Single AI coordinator instance
- `MLXCacheManager`: Cached expensive filesystem operations

**Performance Impact**:
- Eliminates redundant initialization overhead
- Prevents resource conflicts between multiple instances
- Reduces memory footprint through shared instances

### Intelligent Caching System

**Cache implementations for expensive operations**:

| Operation | Cache Duration | Impact |
|-----------|---------------|---------|
| Directory validation | 30 seconds | Prevents redundant filesystem scans |
| Manual download checks | 2 seconds | Reduces process check overhead |
| Model readiness state | Session-based | Eliminates repeated validation |

**Cache Hit/Miss Logging**:
```
🎯 [CACHE HIT] Using cached manual download check result
💾 [CACHE MISS] Performing fresh directory scan - caching for 30s
```

### Debouncing and Rate Limiting

**AI readiness checks now include**:
- **Debouncing**: Prevents rapid successive calls
- **State caching**: Remembers readiness state to avoid rechecks
- **Notification coordination**: Single notification wakes all waiting processes

**Before optimization**: 300+ `isAIReady()` calls during startup
**After optimization**: Single async wait with notification-based completion

### Initialization Guards

**Concurrent initialization prevention**:
- `isInitializationInProgress` flags prevent duplicate startup sequences
- Thread-safe singleton creation with `@MainActor` coordination
- Automatic cleanup of initialization state on completion/failure

### Logging and Debug Information

**Performance monitoring with categorized logging**:
- `🚀 [ASYNC WAIT]`: Async operation tracking
- `⚡ [SINGLETON]`: Singleton lifecycle events  
- `🎯 [CACHE HIT/MISS]`: Cache performance metrics
- `🔄 [DEBOUNCE]`: Rate limiting effectiveness
- `⏱️ [TIMING]`: Operation duration tracking

### Measured Performance Improvements

**Startup metrics (before → after optimization)**:
- AI readiness checks: 300+ calls → 1 async wait
- Model service instances: 3+ concurrent → 1 singleton
- Cache directory scans: Multiple per second → 1 per 30 seconds
- CPU usage during startup: High polling → Minimal notification-based
- Memory usage: Reduced through singleton pattern and caching

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
