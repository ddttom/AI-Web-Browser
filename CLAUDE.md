# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a native macOS AI-powered web browser built with SwiftUI and Swift 6. The application integrates local AI capabilities using Apple's MLX framework for on-device inference, with optional cloud AI providers (OpenAI, Anthropic, Gemini). The codebase emphasizes privacy-first design, performance optimization, and production-ready logging architecture.

## Build System & Commands

### Primary Development Commands
```bash
# Build and run debug version (recommended for development)
npm run run

# Build release version
npm run build

# Build debug version only
npm run build:debug

# Run tests
npm run test

# Clean build artifacts
npm run clean

# Complete clean and rebuild
npm run clean:build

# Kill any running xcodebuild processes
npm run kill-builds
```

### Alternative Xcode Commands
```bash
# Open project in Xcode
open Web.xcodeproj

# Manual xcodebuild commands (if npm scripts fail)
xcodebuild -project Web.xcodeproj -scheme Web -configuration Debug build
xcodebuild -project Web.xcodeproj -scheme Web -configuration Release build
xcodebuild -project Web.xcodeproj -scheme Web -destination 'platform=macOS' test
```

### AI Model Management
```bash
# Download required AI models (recommended before first build)
./scripts/manual_model_download.sh

# Force re-download models
./scripts/manual_model_download.sh -f

# Verify model integrity
./scripts/verify_model.sh

# Clear models (for troubleshooting)
./scripts/clear_model.sh
```

## Architecture Overview

### Core Architecture Pattern
- **MVVM Architecture**: SwiftUI Views ↔ ViewModels ↔ Services ↔ Models
- **Singleton Services**: Core services use singleton pattern with initialization guards
- **Async/Await Coordination**: Swift 6 compliant concurrency with MainActor isolation
- **Privacy-First**: Local AI processing with optional cloud provider fallback

### Key Service Layer Components

**AI System (`Web/AI/`)**:
- `MLXModelService`: Core AI model management and coordination (singleton)
- `AIAssistant`: Main AI coordinator managing conversations and context (singleton)
- `SimplifiedMLXRunner`: Direct MLX model execution
- `MLXCacheManager`: Model file caching and validation
- `AIProvider`: Abstract base for cloud AI providers (OpenAI, Anthropic, Gemini)
- `PrivacyManager`: Handles AI privacy settings and data protection

**Core Services (`Web/Services/`)**:
- `TabManager`: Browser tab lifecycle and hibernation
- `SecurityMonitor`: Multi-layered security monitoring
- `HistoryService`: Browsing history management
- `BookmarkService`: Bookmark organization
- `DownloadManager`: File download coordination

**WebKit Integration**:
- Native WebKit rendering through WKWebView
- Custom WebKit security validation
- Mixed content management
- CSP (Content Security Policy) enforcement

### Directory Structure Significance

```
Web/AI/                    # Complete AI system isolation
├── Agent/                 # AI agent framework with JS execution
├── Services/              # AI service providers and coordination
├── Runners/               # MLX model execution layer
├── Utils/                 # AI-specific utilities (caching, memory)
└── Views/                 # AI UI components (sidebar, chat)

Web/Services/              # Core browser services
Web/ViewModels/            # Business logic layer (TabManager, etc.)
Web/Views/Components/      # Reusable UI components
```

## Critical Development Patterns

### Singleton Pattern Implementation
All major services use guarded singleton initialization:
```swift
static let shared: ServiceName = {
    AppLog.debug("🚀 [SINGLETON] ServiceName initializing")
    return ServiceName()
}()
private static var hasInitialized = false
```

### AI Initialization Coordination
The AI system uses async notification pattern (not polling) for coordination:
- `MLXModelService` handles model loading with smart initialization
- `AIAssistant` waits for AI readiness using `withCheckedContinuation`
- Race condition prevention through proper async coordination

### Logging Architecture
Production-aware logging system:
```swift
AppLog.debug()    // Only in debug builds with verbose flag
AppLog.info()     // Only in debug builds with verbose flag  
AppLog.essential()  // Important messages in both debug and release
AppLog.warn()     // Warnings (filtered for system noise)
AppLog.error()    // Errors (filtered for system noise)
```

Enable verbose logging: `defaults write com.example.Web App.VerboseLogs -bool YES`

## Swift 6 Concurrency Requirements

- All UI updates must use `@MainActor` annotation
- Services properly isolated to background queues where appropriate
- Async/await patterns for AI coordination (no polling loops)
- Proper capture lists in concurrent closures: `[weak self]`
- Sendable protocol compliance for thread-safe data passing

## AI Model Integration

### Local MLX Models
- **Primary Model**: Gemma 2 2B (4-bit quantized) for Apple Silicon
- **Cache Location**: `~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/`
- **Smart Initialization**: Detects existing downloads, coordinates with manual scripts
- **Validation**: File completeness and size checks before loading

### Cloud Providers
- OpenAI, Anthropic, Gemini integration through unified `AIProvider` interface
- BYOK (Bring Your Own Key) model with secure credential storage
- Fallback mechanism from local to cloud providers

## Security Architecture

### Multi-Layer Security
- `SecurityMonitor`: Runtime security monitoring
- `FileSecurityValidator`: Download validation
- `CertificateManager`: TLS certificate handling
- `SafeBrowsingManager`: URL safety checks
- `MalwareScanner`: Local heuristic scanning

### Privacy Controls
- All AI processing defaults to local (MLX)
- Granular privacy settings per AI provider
- No telemetry without explicit user consent
- Secure credential storage in macOS Keychain

## Performance Optimization Patterns

### Memory Management
- Tab hibernation for unused tabs
- Lazy AI model loading
- Intelligent caching with 30-second directory cache
- Debounced AI readiness checks (2-second threshold)

### Startup Optimization
- Singleton pattern prevents duplicate initializations
- Async notification system eliminates polling overhead
- Production logging suppresses verbose debug output
- Smart model discovery avoids unnecessary filesystem scans

## Testing Strategy

- Unit tests in `WebTests/`
- UI tests in `WebUITests/`
- Manual model download script testing for AI components
- Security validation testing for download components

## Debugging & Troubleshooting

### AI Issues
1. Run model download script first: `./scripts/manual_model_download.sh`
2. Enable verbose logging: `defaults write com.example.Web App.VerboseLogs -bool YES`
3. Check model cache: `./scripts/verify_model.sh`
4. Monitor AI initialization in logs for race conditions

### Build Issues
1. Clean build: `npm run clean:build`
2. Kill running builds: `npm run kill-builds`
3. Verify Xcode version (15.0+) and macOS (14.0+)
4. Check Apple Silicon requirement for AI features

### Performance Issues
1. Monitor tab hibernation behavior
2. Check for polling loops (should use async notifications)
3. Verify singleton pattern implementation
4. Review memory usage patterns in AI model loading