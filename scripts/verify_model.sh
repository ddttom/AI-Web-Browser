#!/bin/bash

# Model Verification Script
# This script verifies that manually downloaded model files are accessible to the app

# Debug function for consistent message formatting
debug_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo "🔍 [DEBUG $timestamp] [$level] $message"
}

debug_log "INFO" "Script started - Model Verification"
echo "🔍 Model Verification Script"
echo "============================"
echo ""

# Model configuration (must match manual_model_download.sh)
MODEL_NAME="gemma-2-2b-it-4bit"
CACHE_DIR="$HOME/.cache/huggingface/hub/models--mlx-community--${MODEL_NAME}"
SNAPSHOT_DIR="${CACHE_DIR}/snapshots/main"

# Required files for MLX model (must match manual_model_download.sh)
FILES=(
    "config.json"
    "tokenizer.json"
    "tokenizer_config.json"
    "special_tokens_map.json"
    "model.safetensors"
)

debug_log "INFO" "Checking model configuration paths"
echo "📍 Model Configuration:"
echo "   Model Name: ${MODEL_NAME}"
echo "   Cache Directory: ${CACHE_DIR}"
echo "   Snapshot Directory: ${SNAPSHOT_DIR}"
echo ""

debug_log "INFO" "Verifying directory structure"
echo "🏗️  Directory Structure Verification:"

# Check cache directory
if [[ -d "${CACHE_DIR}" ]]; then
    echo "  ✅ Cache directory exists: ${CACHE_DIR}"
    debug_log "INFO" "Cache directory confirmed: ${CACHE_DIR}"
    
    # List contents of cache directory
    echo "  📋 Cache directory contents:"
    ls -la "${CACHE_DIR}" | while read line; do
        echo "    ${line}"
    done
else
    echo "  ❌ Cache directory missing: ${CACHE_DIR}"
    debug_log "ERROR" "Cache directory not found: ${CACHE_DIR}"
    exit 1
fi

# Check snapshots directory
if [[ -d "${CACHE_DIR}/snapshots" ]]; then
    echo "  ✅ Snapshots directory exists: ${CACHE_DIR}/snapshots"
    debug_log "INFO" "Snapshots directory confirmed"
    
    # List snapshots
    echo "  📋 Snapshots directory contents:"
    ls -la "${CACHE_DIR}/snapshots" | while read line; do
        echo "    ${line}"
    done
else
    echo "  ❌ Snapshots directory missing: ${CACHE_DIR}/snapshots"
    debug_log "ERROR" "Snapshots directory not found"
    exit 1
fi

# Check main snapshot directory
if [[ -d "${SNAPSHOT_DIR}" ]]; then
    echo "  ✅ Main snapshot directory exists: ${SNAPSHOT_DIR}"
    debug_log "INFO" "Main snapshot directory confirmed: ${SNAPSHOT_DIR}"
else
    echo "  ❌ Main snapshot directory missing: ${SNAPSHOT_DIR}"
    debug_log "ERROR" "Main snapshot directory not found: ${SNAPSHOT_DIR}"
    exit 1
fi

echo ""
debug_log "INFO" "Verifying model files"
echo "📄 Model Files Verification:"

cd "${SNAPSHOT_DIR}"
debug_log "INFO" "Changed to snapshot directory: ${SNAPSHOT_DIR}"

# Check each required file
all_files_valid=true
total_size=0

for file in "${FILES[@]}"; do
    debug_log "INFO" "Checking file: ${file}"
    
    if [[ -f "${file}" ]]; then
        # File exists - check size and permissions
        size_bytes=$(stat -f%z "${file}" 2>/dev/null || echo "0")
        size_human=$(du -h "${file}" | cut -f1)
        permissions=$(ls -l "${file}" | cut -d' ' -f1)
        owner=$(ls -l "${file}" | cut -d' ' -f3)
        
        echo "  ✅ ${file}:"
        echo "    📏 Size: ${size_human} (${size_bytes} bytes)"
        echo "    🔐 Permissions: ${permissions}"
        echo "    👤 Owner: ${owner}"
        echo "    📍 Full path: ${SNAPSHOT_DIR}/${file}"
        
        total_size=$((total_size + size_bytes))
        
        # Check if file is readable
        if [[ -r "${file}" ]]; then
            echo "    ✅ File is readable"
            debug_log "INFO" "File ${file} is readable"
        else
            echo "    ❌ File is not readable"
            debug_log "ERROR" "File ${file} is not readable"
            all_files_valid=false
        fi
        
        # Check if file is non-empty
        if [[ $size_bytes -gt 10 ]]; then
            echo "    ✅ File has valid size"
            debug_log "INFO" "File ${file} has valid size: ${size_bytes} bytes"
        else
            echo "    ❌ File is too small or empty"
            debug_log "ERROR" "File ${file} is too small: ${size_bytes} bytes"
            all_files_valid=false
        fi
        
    else
        echo "  ❌ ${file}: File does not exist"
        debug_log "ERROR" "File ${file} does not exist at: ${SNAPSHOT_DIR}/${file}"
        all_files_valid=false
    fi
    echo ""
done

# Calculate total size
if [[ $total_size -gt 0 ]]; then
    total_size_human=$(echo "$total_size" | awk '{
        if ($1 >= 1073741824) printf "%.1fG", $1/1073741824
        else if ($1 >= 1048576) printf "%.1fM", $1/1048576
        else if ($1 >= 1024) printf "%.1fK", $1/1024
        else printf "%dB", $1
    }')
    echo "💾 Total model size: ${total_size_human}"
fi

echo ""
debug_log "INFO" "Verification summary"
echo "📊 Verification Summary:"

if [[ "$all_files_valid" == true ]]; then
    echo "  ✅ All model files are present and valid"
    echo "  ✅ Files are readable and have correct permissions"
    echo "  ✅ Directory structure is correct"
    debug_log "INFO" "All verification checks passed"
    
    echo ""
    echo "🔍 App Integration Information:"
    echo "   Internal App Model ID: gemma3_2B_4bit"
    echo "   HuggingFace Repository: mlx-community/gemma-2-2b-it-4bit"
    echo "   Cache Directory Name: models--mlx-community--gemma-2-2b-it-4bit"
    echo "   Expected App Search Path: ${SNAPSHOT_DIR}"
    echo ""
    echo "✅ Model files should be detectable by the Web app"
    echo "   If the app still reports validation errors, there may be an issue"
    echo "   with the app's cache detection logic or MLX validation process."
    
else
    echo "  ❌ Some model files are missing or invalid"
    echo "  ❌ The app will not be able to load these files"
    debug_log "ERROR" "Verification failed - files are not valid"
    
    echo ""
    echo "🔧 Recommended Actions:"
    echo "   1. Run: ./scripts/clear_model.sh"
    echo "   2. Run: ./scripts/manual_model_download.sh -f"
    echo "   3. Run this verification script again"
fi

echo ""
echo "💡 Next Steps:"
echo "   • Start the Web app and check for '[SMART INIT]' and '[CACHE DEBUG]' messages"
echo "   • Look for successful model detection in the app logs"
echo "   • If issues persist, the problem is likely in the app's validation logic"