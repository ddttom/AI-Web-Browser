# MLX Model Download Error Fix

## Issue Description

**Error Message:**
```
AI initialization failed: MLX model download failed: MLX model download failed: "tokenizer.json.3f289bc05132635a8bc7aca7aa21255efd5e18f3710f43e3cdb96bcd41be4922.incomplete" couldn't be moved to "gemma-2-2b-it-4bit" because either the former doesn't exist, or the folder containing the latter doesn't exist.
```

**When it occurs:**
- During app startup when the MLX model service tries to automatically download the default Gemma 2 2B model
- The error indicates a failure in the Hugging Face model download process managed by MLX-Swift

## Root Cause Analysis

The error occurs due to several potential issues in the MLX model download pipeline:

1. **Incomplete Download**: Network interruptions cause partial downloads that leave `.incomplete` files
2. **File System Race Conditions**: The MLX framework attempts to move incomplete files before they're fully written
3. **Directory Structure Issues**: Missing intermediate directories in the Hugging Face cache structure
4. **Corrupted Cache State**: Previous failed downloads leave the cache in an inconsistent state

## Technical Details

### Current Download Flow
```
MLXModelService.initializeAI() 
→ SimplifiedMLXRunner.ensureLoaded()
→ LLMModelFactory.loadContainer()
→ Hugging Face download via MLX-Swift
→ File organization failure
```

### Cache Locations
- **Hugging Face Cache**: `~/.cache/huggingface/hub/`
- **MLX Cache**: `~/Library/Caches/MLXCache/`
- **Model Files**: `config.json`, `tokenizer.json`, `model.safetensors`

## Solution Implementation

### 1. Manual Download Script (Primary Solution)

**File:** [`scripts/manual_model_download.sh`](../scripts/manual_model_download.sh)

**⚠️ Recommended Approach**: Due to persistent issues with automatic MLX model downloads, the manual download script provides a reliable solution:

```bash
# Run from project root directory
./scripts/manual_model_download.sh
```

**Script Features:**
- Automatically cleans corrupted cache
- Downloads all required model files directly from Hugging Face
- Verifies file integrity and sizes
- Provides clear progress updates and error handling
- Creates proper Hugging Face cache directory structure

**Successfully Downloads:**
- `config.json` (4.0K) - Model configuration
- `tokenizer.json` (17M) - Tokenizer data
- `tokenizer_config.json` (48K) - Tokenizer configuration
- `special_tokens_map.json` (4.0K) - Special tokens mapping
- `model.safetensors` (1.3G) - Main model weights

**Total Size**: ~1.35GB

### 2. Enhanced Error Handling and Recovery

**File:** [`Web/AI/Services/MLXModelService.swift`](../Web/AI/Services/MLXModelService.swift)

Added robust error handling with:
- Automatic cache cleanup for corrupted downloads
- Retry logic with exponential backoff
- Detailed error logging for debugging
- Graceful fallback mechanisms

### 2. Cache Validation and Cleanup

**File:** [`Web/AI/Utils/MLXCacheManager.swift`](../Web/AI/Utils/MLXCacheManager.swift)

New utility class providing:
- Detection and removal of incomplete downloads
- Validation of model file integrity
- Cache directory structure verification
- Safe cleanup operations

### 3. Download Retry Logic

**File:** [`Web/AI/Services/MLXDownloadManager.swift`](../Web/AI/Services/MLXDownloadManager.swift)

Implements:
- Exponential backoff retry strategy
- Network connectivity checks
- Download progress monitoring
- Timeout handling

### 4. Model Validation

Enhanced model validation in [`SimplifiedMLXRunner.swift`](../Web/AI/Runners/SimplifiedMLXRunner.swift):
- Pre-load file existence checks
- Model configuration validation
- Tokenizer integrity verification
- Graceful error recovery

## Code Changes

### MLXModelService Enhancements

```swift
// Added comprehensive error handling
private func downloadModelIfNeeded() async throws {
    let maxRetries = 3
    var lastError: Error?
    
    for attempt in 1...maxRetries {
        do {
            // Clean up any corrupted cache before attempting download
            try await MLXCacheManager.shared.cleanupCorruptedCache(for: model.modelId)
            
            // Attempt download with enhanced error handling
            try await performDownloadWithValidation(model: model)
            return
            
        } catch {
            lastError = error
            AppLog.error("Download attempt \(attempt) failed: \(error.localizedDescription)")
            
            if attempt < maxRetries {
                let delay = pow(2.0, Double(attempt)) // Exponential backoff
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    throw MLXModelError.downloadFailed("Failed after \(maxRetries) attempts: \(lastError?.localizedDescription ?? "Unknown error")")
}
```

### Cache Manager Implementation

```swift
class MLXCacheManager {
    static let shared = MLXCacheManager()
    
    func cleanupCorruptedCache(for modelId: String) async throws {
        let cacheDirectories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub"),
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("MLXCache")
        ].compactMap { $0 }
        
        for cacheDir in cacheDirectories {
            try await cleanupIncompleteFiles(in: cacheDir, for: modelId)
        }
    }
    
    private func cleanupIncompleteFiles(in directory: URL, for modelId: String) async throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for item in contents {
            if item.lastPathComponent.contains(".incomplete") || 
               item.lastPathComponent.contains(modelId) {
                try FileManager.default.removeItem(at: item)
                AppLog.debug("Cleaned up corrupted cache file: \(item.lastPathComponent)")
            }
        }
    }
}
```

## User-Facing Improvements

### 1. Better Error Messages
- Clear explanation of what went wrong
- Suggested actions for users
- Progress indicators during downloads

### 2. Automatic Recovery System
- Detects tokenizer corruption automatically
- Performs aggressive cache cleanup
- Retries download with fresh state
- Provides clear feedback on recovery attempts

### 3. Manual Download Option
- Fallback UI when automatic download fails
- Direct links to model files
- Step-by-step manual installation guide

### 4. Cache Management UI
- View cache status and size
- Clear corrupted downloads
- Retry failed downloads
- Real-time status updates

## Testing Strategy

### 1. Network Condition Testing
- Simulate network interruptions during download
- Test with slow/unstable connections
- Verify retry logic works correctly

### 2. Cache State Testing
- Test with corrupted cache directories
- Verify cleanup operations work safely
- Test concurrent download scenarios

### 3. Error Recovery Testing
- Test all error paths and recovery mechanisms
- Verify user-friendly error messages
- Test manual download fallbacks

## Prevention Measures

### 1. Proactive Cache Health Checks
- Regular validation of downloaded models
- Automatic cleanup of old/corrupted files
- Health status reporting in UI

### 2. Improved Download Monitoring
- Real-time progress tracking
- Network quality assessment
- Predictive retry scheduling

### 3. User Education
- Clear documentation about model requirements
- Troubleshooting guides
- Best practices for network conditions

## Resolution Verification

### Intelligent AI Initialization Implementation

**✅ Smart Startup Coordination Implemented:**

1. **Manual Download Detection**: App now detects active manual download processes via lock files and process scanning
2. **Graceful Waiting**: App pauses automatic initialization when manual downloads are detected
3. **Existing Model Recognition**: App instantly recognizes and loads pre-downloaded models
4. **File Lock Coordination**: Manual script creates lock file that app respects
5. **Conflict Prevention**: Zero race conditions between manual and automatic processes

### Manual Download Script Testing

**✅ Successfully Tested and Verified:**

1. **Script Execution**: `./scripts/manual_model_download.sh` completed successfully
2. **File Lock Creation**: Script creates `.manual_download_lock` file during download
3. **File Downloads**: All required files downloaded with correct sizes:
   - `config.json` (4.0K)
   - `tokenizer.json` (17M) 
   - `tokenizer_config.json` (48K)
   - `special_tokens_map.json` (4.0K)
   - `model.safetensors` (1.3G)
4. **Cache Structure**: Proper Hugging Face directory structure created
5. **File Integrity**: All files verified as complete and uncorrupted
6. **Lock Cleanup**: Lock file automatically removed on completion
7. **Total Download**: ~1.35GB successfully downloaded

**Cache Location**: `~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/snapshots/main/`

### Verification Steps

After implementing the fix:

1. **✅ Clean Install Test**: Manual download script successfully created fresh model cache
2. **✅ Network Interruption Test**: Script handles download failures gracefully
3. **✅ Corrupted Cache Test**: Script cleans existing corrupted files before download
4. **✅ Retry Logic Test**: Automatic recovery system provides clear fallback guidance
5. **✅ User Experience Test**: Error messages guide users to manual script solution

## Related Files Modified

- [`Web/AI/Services/MLXModelService.swift`](../Web/AI/Services/MLXModelService.swift) - Enhanced error handling
- [`Web/AI/Runners/SimplifiedMLXRunner.swift`](../Web/AI/Runners/SimplifiedMLXRunner.swift) - Model validation
- [`Web/AI/Utils/MLXCacheManager.swift`](../Web/AI/Utils/MLXCacheManager.swift) - New cache management utility
- [`Web/AI/Services/MLXDownloadManager.swift`](../Web/AI/Services/MLXDownloadManager.swift) - New download manager
- [`docs/Troubleshooting.md`](Troubleshooting.md) - Updated with MLX model issues

## Future Enhancements

1. **Parallel Downloads**: Download model components in parallel for faster setup
2. **Delta Updates**: Only download changed model components
3. **Peer-to-Peer Sharing**: Share models between app instances on same network
4. **Cloud Backup**: Backup validated models to user's cloud storage