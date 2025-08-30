# Troubleshooting Guide

## Code Signing Issues

### Problem: Xcode Build Fails with Code Signing Errors

**Error Message:**
```
No Accounts: Add a new account in Accounts settings.
No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "YYMLDY74QZ" with a private key was found.
```

**Root Cause:**
The project had conflicting code signing settings in the Xcode project configuration. The main app target was configured with:
- `CODE_SIGNING_REQUIRED = NO` (code signing disabled)
- `CODE_SIGN_IDENTITY = "Apple Development"` (conflicting setting)
- `CODE_SIGN_STYLE = Automatic` (conflicting setting)
- `DEVELOPMENT_TEAM = YYMLDY74QZ` (conflicting setting)

When `CODE_SIGNING_REQUIRED = NO`, the other code signing settings should not be present as they create a contradiction.

**Solution:**
1. Open the project file [`Web.xcodeproj/project.pbxproj`](../Web.xcodeproj/project.pbxproj)
2. Remove the conflicting code signing settings from both Debug and Release configurations
3. Keep only `CODE_SIGNING_REQUIRED = NO` for development builds

**Changes Made:**
- Removed `CODE_SIGN_IDENTITY = "Apple Development"`
- Removed `CODE_SIGN_STYLE = Automatic`
- Removed `DEVELOPMENT_TEAM = YYMLDY74QZ`
- Kept `CODE_SIGNING_REQUIRED = NO`

**Result:**
The build now completes successfully without requiring Apple Developer account credentials or signing certificates for development builds.

### Alternative Solutions

If you need code signing enabled for distribution:

1. **Add Apple Developer Account:**
   - Open Xcode → Preferences → Accounts
   - Add your Apple Developer account
   - Ensure certificates are properly installed

2. **Configure Automatic Signing:**
   - Set `CODE_SIGNING_REQUIRED = YES`
   - Set `CODE_SIGN_STYLE = Automatic`
   - Set `DEVELOPMENT_TEAM = [Your Team ID]`
   - Remove `CODE_SIGN_IDENTITY` to let Xcode choose automatically

3. **Manual Signing:**
   - Set `CODE_SIGNING_REQUIRED = YES`
   - Set `CODE_SIGN_STYLE = Manual`
   - Set `CODE_SIGN_IDENTITY = [Specific Certificate Name]`
   - Set `PROVISIONING_PROFILE_SPECIFIER = [Profile Name]`

### Prevention

To avoid similar issues in the future:
- Be consistent with code signing settings across Debug/Release configurations
- Don't mix `CODE_SIGNING_REQUIRED = NO` with other code signing settings
- Use Xcode's project settings UI instead of manually editing the project file when possible
- Document any manual changes to the project configuration

## Build Performance

The project includes several heavy dependencies (MLX frameworks, Swift Transformers) that can make initial builds slow. Subsequent builds should be faster due to incremental compilation.

**First Build:** ~2-3 minutes (includes downloading and compiling MLX frameworks)
**Incremental Builds:** ~30-60 seconds (only changed files)

## Common Build Issues

### Missing Dependencies
If you encounter missing framework errors, ensure all Swift Package Manager dependencies are resolved:
```bash
xcodebuild -resolvePackageDependencies
```

### Clean Build
If you encounter persistent build issues, try a clean build:
```bash
xcodebuild clean -project Web.xcodeproj -scheme Web
```

### Derived Data Issues
If builds fail unexpectedly, clear derived data:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

## MLX Model Download Issues

### Problem: MLX AI Model Download Failed with "config.json" or "tokenizer.json" Errors

**Error Messages:**
```
AI initialization failed: MLX model download failed: "tokenizer.json.3f289bc05132635a8bc7aca7aa21255efd5e18f3710f43e3cdb96bcd41be4922.incomplete" couldn't be moved to "gemma-2-2b-it-4bit" because either the former doesn't exist, or the folder containing the latter doesn't exist.
```

```
The file "config.json" couldn't be opened because there is no such file.
```

**Root Cause:**
These errors occur when the MLX framework's Hugging Face model download process is interrupted, leaving incomplete or corrupted files in the cache. This typically happens due to:
- Network interruptions during download
- Insufficient disk space
- File system permissions issues
- Corrupted cache state from previous failed downloads

**Solutions:**

#### Intelligent Startup Coordination (New)
The app now includes **smart startup AI initialization** that coordinates with manual downloads:
1. **Manual Download Detection**: Automatically detects active manual download processes
2. **Graceful Waiting**: Pauses automatic initialization when manual downloads are active
3. **Existing Model Recognition**: Instantly recognizes and loads pre-downloaded models
4. **Conflict Prevention**: Avoids cache interference during manual download processes
5. **Timeout Handling**: Falls back to automatic download if manual process stalls
6. **Process Monitoring**: Real-time monitoring of manual download progress

#### Automatic Recovery (Enhanced)
The app also includes enhanced automatic recovery mechanisms:
1. **Tokenizer Corruption Detection**: Specifically detects and handles tokenizer file corruption
2. **Aggressive Cache Cleanup**: Removes corrupted tokenizer files and incomplete downloads
3. **Model State Reset**: Clears MLX runner state before retry attempts
4. **Retry Logic**: Downloads are retried up to 3 times with exponential backoff
5. **Validation**: Downloaded models are validated before use
6. **Recovery Feedback**: Clear logging shows recovery attempts and results

#### Manual Recovery Steps

**When Automatic Recovery Fails:**
If you see the error "Automatic recovery failed: Model recovery failed - files still corrupted after cleanup", follow these steps:

**Option 1: Automated Script (Recommended)**
Run the provided manual download script:
```bash
# Navigate to the project directory
cd /path/to/Web

# Run the manual download script
./scripts/manual_model_download.sh
```

This script will:
- Clean existing corrupted cache
- Download all required model files directly from Hugging Face
- Verify file integrity
- Provide clear status updates

**Option 2: Manual Steps**</search>
</search_and_replace>

1. **Complete Cache Reset:**
   ```bash
   # Remove ALL Hugging Face cache
   rm -rf ~/.cache/huggingface/
   
   # Remove ALL MLX cache
   rm -rf ~/Library/Caches/MLXCache/
   
   # Remove app-specific cache
   rm -rf ~/Library/Caches/com.web.Web/
   ```

2. **Manual Model Download (Alternative Method):**
   ```bash
   # Create the directory structure
   mkdir -p ~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/snapshots/main
   
   # Download model files directly using curl
   cd ~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/snapshots/main
   
   # Download required files
   curl -L -o config.json "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit/resolve/main/config.json"
   curl -L -o tokenizer.json "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit/resolve/main/tokenizer.json"
   curl -L -o tokenizer_config.json "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit/resolve/main/tokenizer_config.json"
   curl -L -o special_tokens_map.json "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit/resolve/main/special_tokens_map.json"
   curl -L -o model.safetensors "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit/resolve/main/model.safetensors"
   ```

3. **Verify Downloads:**
   ```bash
   # Check all files are present and not empty
   ls -la ~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/snapshots/main/
   
   # Verify file sizes (should not be 0 bytes)
   du -h ~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/snapshots/main/*
   ```

4. **Alternative: Use Git LFS:**
   ```bash
   # Install git-lfs if not already installed
   brew install git-lfs
   
   # Clone the model repository
   cd ~/.cache/huggingface/hub/
   git lfs clone https://huggingface.co/mlx-community/gemma-2-2b-it-4bit models--mlx-community--gemma-2-2b-it-4bit
   ```

5. **Check Disk Space:**
   ```bash
   df -h
   ```
   Ensure you have at least 5GB free space for model downloads.

6. **Reset App State:**
   - Quit the app completely
   - Clear caches as above
   - Restart the app to trigger fresh download

7. **Network Troubleshooting:**
   - Ensure stable internet connection
   - Check if corporate firewall blocks Hugging Face downloads
   - Try downloading during off-peak hours
   - Use VPN if corporate network blocks access

#### Advanced Troubleshooting

**Check Cache Status:**
The app logs cache information during startup. Look for:
```
Cache status before download: X.X GB, N models
MLX model download: XX%
```

**Manual Model Verification:**
```bash
# Check if model directory exists
ls -la ~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/

# Verify required files
find ~/.cache/huggingface/hub/ -name "config.json" -o -name "tokenizer.json"
```

**Force Clean Download:**
```bash
# Complete cache reset
rm -rf ~/.cache/huggingface/
rm -rf ~/Library/Caches/MLXCache/
rm -rf ~/Library/Caches/com.web.Web/
```

#### Prevention

1. **Stable Network**: Ensure reliable internet during first app launch
2. **Sufficient Space**: Keep at least 10GB free disk space
3. **Avoid Interruption**: Don't quit the app during initial model download
4. **Regular Cleanup**: The app automatically manages cache, but manual cleanup can help if issues persist

#### Error-Specific Solutions

**"tokenizer.json.*.incomplete" errors:**
- Indicates interrupted download
- App will automatically retry with cleanup
- If persistent, manually clear cache and restart

**"config.json" not found:**
- Model configuration missing
- Usually resolved by cache cleanup and retry
- Check network connectivity to huggingface.co

**"couldn't be moved" errors:**
- File system permission or space issues
- Check disk space and permissions
- Try running app with different user account if needed

### Model Download Progress Monitoring

The app provides detailed progress information:
- **Checking**: Validating existing cache
- **Downloading**: Active download with percentage
- **Validating**: Verifying downloaded files
- **Ready**: Model loaded and available

If stuck in any state for >5 minutes, restart the app to trigger recovery.

## Swift Compilation Warnings

### Problem: String Interpolation Produces Debug Description for Optional Value

**Error Message:**
```
A String interpolation produces a debug description for an optional value; did you mean to make this explicit? SourceKit [Ln 184, Col 73] SimplifiedMLXRunner.swift[Ln 184, Col 84]: Use 'String (describing:)' to silence this warning SimplifiedMLXRunner.swift[Ln 184, Col 84]: Provide a default value to avoid this warning
```

**Root Cause:**
This warning occurs when using string interpolation with optional values in Swift. When an optional value is interpolated directly into a string, Swift produces debug descriptions like "Optional(512)" instead of the actual value "512".

**Solution:**
Use the nil coalescing operator (`??`) to provide default values for optional properties in string interpolation:

```swift
// Before (produces warning):
"Starting generation with maxTokens=\(parameters.maxTokens), temp=\(parameters.temperature)"

// After (fixed):
"Starting generation with maxTokens=\(parameters.maxTokens ?? 512), temp=\(parameters.temperature ?? 0.7)"
```

**Alternative Solutions:**
1. **Using String(describing:)** (silences warning but shows "Optional(value)"):
   ```swift
   "maxTokens=\(String(describing: parameters.maxTokens))"
   ```

2. **Force unwrapping** (only if you're certain the value isn't nil):
   ```swift
   "maxTokens=\(parameters.maxTokens!)"
   ```

3. **Optional binding** (for more complex cases):
   ```swift
   let maxTokensText = parameters.maxTokens.map { "\($0)" } ?? "default"
   ```

**Best Practice:**
Always use nil coalescing with meaningful default values as it provides the cleanest output and handles nil cases gracefully without showing debug descriptions in logs.</search></search>
</search_and_replace>