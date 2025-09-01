#!/bin/bash

# Manual MLX Model Download Script
# This script manually downloads the Gemma 2 2B model for MLX when automatic download fails
# Usage: ./manual_model_download.sh [-f|--force]
#   -f, --force    Force download even if files already exist

set -e  # Exit on any error

# Parse command line arguments
FORCE_DOWNLOAD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        -h|--help)
            echo "Manual MLX Model Download Script"
            echo "Usage: $0 [-f|--force] [-h|--help]"
            echo ""
            echo "Options:"
            echo "  -f, --force    Force download even if files already exist"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "This script downloads the Gemma 2 2B MLX model files to:"
            echo "  ~/.cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/snapshots/main/"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Debug function for consistent message formatting
debug_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo "🔍 [DEBUG $timestamp] [$level] $message"
}

if [[ "$FORCE_DOWNLOAD" == true ]]; then
    debug_log "INFO" "Script started - Manual MLX Model Download (FORCE MODE)"
    echo "🔥 Manual MLX Model Download Script (FORCE MODE)"
    echo "================================================="
    echo "⚠️  Force mode enabled - will re-download all files"
else
    debug_log "INFO" "Script started - Manual MLX Model Download"
    echo "📥 Manual MLX Model Download Script"
    echo "=================================="
fi
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

# Required files for MLX model
FILES=(
    "config.json"
    "tokenizer.json"
    "tokenizer_config.json"
    "special_tokens_map.json"
    "model.safetensors"
)

cd "${SNAPSHOT_DIR}"
debug_log "INFO" "Changed to snapshot directory: ${SNAPSHOT_DIR}"

# Skip file existence check if force mode is enabled
if [[ "$FORCE_DOWNLOAD" == true ]]; then
    debug_log "INFO" "Force mode enabled - skipping file existence check"
    echo "🔥 Force mode: Will re-download all files regardless of existing files"
    echo "🧹 Cleaning existing files..."
    rm -f "${SNAPSHOT_DIR}"/*.json
    rm -f "${SNAPSHOT_DIR}"/*.safetensors
    rm -f "${SNAPSHOT_DIR}"/*.incomplete
    debug_log "INFO" "Existing files cleaned for force download"
else
    debug_log "INFO" "Checking if all required files already exist"
    echo "🔍 Checking existing files..."
    
    # Check if all files already exist and are non-empty
    all_files_exist=true
    for file in "${FILES[@]}"; do
        if [[ ! -s "${file}" ]]; then
            debug_log "INFO" "File ${file} is missing or empty"
            all_files_exist=false
            break
        else
            # Get file size safely with error handling
            if size=$(du -h "${file}" 2>/dev/null | cut -f1); then
                debug_log "INFO" "File ${file} exists and is non-empty (${size})"
            else
                debug_log "INFO" "File ${file} exists and is non-empty (size unknown)"
            fi
        fi
    done

    if [[ "$all_files_exist" == true ]]; then
        debug_log "INFO" "All required files already exist - skipping download"
        echo ""
        echo "✅ All model files already exist and are non-empty!"
        echo "📍 Model location: ${SNAPSHOT_DIR}"
        echo ""
        echo "📋 Existing files:"
        for file in "${FILES[@]}"; do
            size=$(du -h "${file}" | cut -f1)
            echo "  ✅ ${file}: ${size}"
        done
        echo ""
        echo "🔍 [SCRIPT DEBUG] Model ID mapping for app coordination:"
        echo "   Internal App Model ID: gemma3_2B_4bit"
        echo "   Hugging Face Model: mlx-community/gemma-2-2b-it-4bit"
        echo "   Cache Directory: models--mlx-community--gemma-2-2b-it-4bit"
        echo "   Full Path: ${SNAPSHOT_DIR}"
        echo ""
        echo "💡 No download needed - you can start the Web app immediately!"
        echo "   The app should detect these existing model files automatically."
        echo "   Use -f or --force to re-download files anyway."
        exit 0
    fi
fi

if [[ "$FORCE_DOWNLOAD" == false ]]; then
    debug_log "INFO" "Some files missing or empty - proceeding with download"
    echo "🧹 Cleaning incomplete files..."
    rm -f "${SNAPSHOT_DIR}"/*.incomplete
    debug_log "INFO" "Incomplete file cleanup completed"
    echo "📥 Downloading missing model files..."
else
    echo "📥 Force downloading all model files..."
fi

debug_log "INFO" "Starting model file downloads"

# Download each file with retry logic
for file in "${FILES[@]}"; do
    debug_log "INFO" "Starting download for file: ${file} -> ${SNAPSHOT_DIR}/${file}"
    echo "  📄 Downloading ${file}..."
    
    # Check if file already exists and is valid (skip check in force mode)
    if [[ "$FORCE_DOWNLOAD" == false && -s "${file}" ]]; then
        debug_log "INFO" "File ${file} already exists and is non-empty, skipping download"
        echo "  ✅ ${file} already exists ($(du -h "${file}" | cut -f1))"
        continue
    elif [[ "$FORCE_DOWNLOAD" == true && -s "${file}" ]]; then
        debug_log "INFO" "Force mode: removing existing file ${file} before download"
        rm -f "${file}"
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