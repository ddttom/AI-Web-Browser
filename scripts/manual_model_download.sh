#!/bin/bash

# Manual MLX Model Download Script
# This script manually downloads the Gemma 2 2B model for MLX when automatic download fails

set -e  # Exit on any error

# Debug function for consistent message formatting
debug_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo "🔍 [DEBUG $timestamp] [$level] $message"
}

debug_log "INFO" "Script started - Manual MLX Model Download"
echo "� Manual MLX Model Download Script"
echo "=================================="
echo ""

debug_log "INFO" "Checking operating system compatibility"
# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script is designed for macOS only"
    exit 1
fi

debug_log "INFO" "Checking for required tools (curl)"
# Check for required tools
if ! command -v curl &> /dev/null; then
    echo "❌ curl is required but not installed"
    exit 1
fi

debug_log "INFO" "Setting up model configuration"
# Model configuration
MODEL_NAME="gemma-2-2b-it-4bit"
MODEL_REPO="mlx-community/gemma-2-2b-it-4bit"
BASE_URL="https://huggingface.co/${MODEL_REPO}/resolve/main"

# Download configuration
MAX_RETRIES=3
RETRY_DELAY=2

# Cache directory
CACHE_DIR="$HOME/.cache/huggingface/hub/models--mlx-community--${MODEL_NAME}"
SNAPSHOT_DIR="${CACHE_DIR}/snapshots/main"

debug_log "INFO" "Creating cache directory structure at: ${CACHE_DIR}"
echo "📁 Setting up cache directory..."
mkdir -p "${SNAPSHOT_DIR}"
debug_log "INFO" "Cache directory created successfully"

# Create lock file to signal manual download in progress
LOCK_FILE="${CACHE_DIR}/.manual_download_lock"
debug_log "INFO" "Creating download lock file at: ${LOCK_FILE}"
echo "🔒 Creating download lock file..."
echo "Manual download started at $(date)" > "${LOCK_FILE}"
debug_log "INFO" "Lock file created successfully"

# Cleanup function to remove lock file on exit
cleanup() {
    debug_log "INFO" "Cleanup function called - removing lock file"
    echo "🧹 Cleaning up lock file..."
    rm -f "${LOCK_FILE}"
    debug_log "INFO" "Cleanup completed"
}

# Set trap to cleanup on script exit (success or failure)
trap cleanup EXIT

debug_log "INFO" "Cleaning existing files from snapshot directory"
echo "🧹 Cleaning existing files..."
rm -f "${SNAPSHOT_DIR}"/*.json
rm -f "${SNAPSHOT_DIR}"/*.safetensors
rm -f "${SNAPSHOT_DIR}"/*.incomplete
debug_log "INFO" "File cleanup completed"

debug_log "INFO" "Starting model file downloads"
echo "📥 Downloading model files..."
cd "${SNAPSHOT_DIR}"
debug_log "INFO" "Changed to snapshot directory: ${SNAPSHOT_DIR}"

# Required files for MLX model
FILES=(
    "config.json"
    "tokenizer.json"
    "tokenizer_config.json"
    "special_tokens_map.json"
    "model.safetensors"
)

# Download each file with retry logic
for file in "${FILES[@]}"; do
    debug_log "INFO" "Starting download for file: ${file} -> ${SNAPSHOT_DIR}/${file}"
    echo "  📄 Downloading ${file}..."
    
    # Check if file already exists and is valid
    if [[ -s "${file}" ]]; then
        debug_log "INFO" "File ${file} already exists and is non-empty, skipping download"
        echo "  ✅ ${file} already exists ($(du -h "${file}" | cut -f1))"
        continue
    fi
    
    # Retry logic for downloads
    retry_count=0
    download_success=false
    
    while [[ $retry_count -lt $MAX_RETRIES && $download_success == false ]]; do
        if [[ $retry_count -gt 0 ]]; then
            debug_log "INFO" "Retry attempt ${retry_count} for ${file}"
            echo "  🔄 Retrying ${file} (attempt $((retry_count + 1))/${MAX_RETRIES})..."
            sleep $RETRY_DELAY
        fi
        
        if curl -L -f -o "${file}" "${BASE_URL}/${file}"; then
            debug_log "INFO" "curl command succeeded for ${file} from ${BASE_URL}/${file} to ${SNAPSHOT_DIR}/${file}"
            # Verify file is not empty
            if [[ -s "${file}" ]]; then
                debug_log "INFO" "File ${file} downloaded and verified non-empty at: ${SNAPSHOT_DIR}/${file}"
                echo "  ✅ ${file} downloaded successfully ($(du -h "${file}" | cut -f1))"
                download_success=true
            else
                debug_log "ERROR" "File ${file} is empty after download at: ${SNAPSHOT_DIR}/${file}"
                echo "  ❌ ${file} is empty, removing and retrying..."
                rm -f "${file}"
                retry_count=$((retry_count + 1))
            fi
        else
            debug_log "ERROR" "curl command failed for ${file} from ${BASE_URL}/${file} to ${SNAPSHOT_DIR}/${file} (attempt $((retry_count + 1)))"
            retry_count=$((retry_count + 1))
        fi
    done
    
    # Check if download ultimately failed
    if [[ $download_success == false ]]; then
        debug_log "ERROR" "Failed to download ${file} after ${MAX_RETRIES} attempts"
        echo "  ❌ Failed to download ${file} after ${MAX_RETRIES} attempts"
        exit 1
    fi
done

echo ""
debug_log "INFO" "Starting download verification phase"
echo "🔍 Verifying downloads..."

# Verify all files exist and are not empty
all_good=true
for file in "${FILES[@]}"; do
    if [[ -s "${file}" ]]; then
        size=$(du -h "${file}" | cut -f1)
        echo "  ✅ ${file}: ${size}"
    else
        echo "  ❌ ${file}: Missing or empty"
        all_good=false
    fi
done

if [[ "$all_good" == true ]]; then
    debug_log "INFO" "All files verified successfully - download completed"
    echo ""
    echo "🎉 Model download completed successfully!"
    echo "📍 Model location: ${SNAPSHOT_DIR}"
    echo ""
    echo "🔍 [SCRIPT DEBUG] Model ID mapping for app coordination:"
    echo "   Internal App Model ID: gemma3_2B_4bit"
    echo "   Hugging Face Model: mlx-community/gemma-2-2b-it-4bit"
    echo "   Cache Directory: models--mlx-community--gemma-2-2b-it-4bit"
    echo "   Full Path: ${SNAPSHOT_DIR}"
    echo ""
    echo "� Next steps:"
    echo "1. Restart the Web app"
    echo "2. The app should now detect the manually downloaded model"
    echo "3. Look for '[CACHE DEBUG]' messages in app logs to verify detection"
    echo "4. If issues persist, check Settings > Model Management for cache status"
    echo ""
    echo "💡 Tip: You can also use the cache management UI in Settings to verify the model"
else
    debug_log "ERROR" "Download verification failed - some files missing or corrupted"
    echo ""
    echo "❌ Download verification failed!"
    echo "Some files are missing or corrupted. Please try running the script again."
    exit 1
fi