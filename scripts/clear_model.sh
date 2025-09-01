#!/bin/bash

# Clear MLX Model Script
# This script removes models downloaded by manual_model_download.sh for testing and troubleshooting

set -e  # Exit on any error

# Debug function for consistent message formatting
debug_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo "🔍 [DEBUG $timestamp] [$level] $message"
}

debug_log "INFO" "Script started - Clear MLX Model"
echo "🗑️  Clear MLX Model Script"
echo "========================="
echo ""

debug_log "INFO" "Checking operating system compatibility"
# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script is designed for macOS only"
    exit 1
fi

debug_log "INFO" "Setting up model configuration"
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

debug_log "INFO" "Checking if model directory exists: ${CACHE_DIR}"
echo "🔍 Checking for existing model files..."

if [[ ! -d "${CACHE_DIR}" ]]; then
    debug_log "INFO" "Model cache directory does not exist"
    echo "✅ No model files found - nothing to clear!"
    echo "📍 Expected location: ${CACHE_DIR}"
    exit 0
fi

if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
    debug_log "INFO" "Snapshot directory does not exist"
    echo "✅ No model files found in snapshots - nothing to clear!"
    echo "📍 Expected location: ${SNAPSHOT_DIR}"
    exit 0
fi

debug_log "INFO" "Checking for model files in: ${SNAPSHOT_DIR}"
cd "${SNAPSHOT_DIR}"

# Check which files exist
existing_files=()
total_size=0
for file in "${FILES[@]}"; do
    if [[ -f "${file}" ]]; then
        size_bytes=$(stat -f%z "${file}" 2>/dev/null || echo "0")
        size_human=$(du -h "${file}" | cut -f1)
        existing_files+=("${file}")
        total_size=$((total_size + size_bytes))
        debug_log "INFO" "Found file: ${file} (${size_human})"
    fi
done

if [[ ${#existing_files[@]} -eq 0 ]]; then
    debug_log "INFO" "No model files found to clear"
    echo "✅ No model files found - nothing to clear!"
    echo "📍 Checked location: ${SNAPSHOT_DIR}"
    exit 0
fi

# Show what will be removed
echo ""
echo "📋 Found ${#existing_files[@]} model file(s) to remove:"
for file in "${existing_files[@]}"; do
    size=$(du -h "${file}" | cut -f1)
    echo "  🗑️  ${file}: ${size}"
done

# Calculate total size
if [[ $total_size -gt 0 ]]; then
    total_size_human=$(echo "$total_size" | awk '{
        if ($1 >= 1073741824) printf "%.1fG", $1/1073741824
        else if ($1 >= 1048576) printf "%.1fM", $1/1048576
        else if ($1 >= 1024) printf "%.1fK", $1/1024
        else printf "%dB", $1
    }')
    echo ""
    echo "💾 Total size to be freed: ${total_size_human}"
fi

echo ""
echo "⚠️  This will permanently delete the downloaded model files!"
echo "📍 Location: ${SNAPSHOT_DIR}"
echo ""

# Confirmation prompt
read -p "❓ Are you sure you want to remove these files? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    debug_log "INFO" "User cancelled operation"
    echo "❌ Operation cancelled - no files were removed"
    exit 0
fi

debug_log "INFO" "User confirmed - proceeding with file removal"
echo ""
echo "🗑️  Removing model files..."

# Remove each file with confirmation
removed_count=0
for file in "${existing_files[@]}"; do
    if [[ -f "${file}" ]]; then
        debug_log "INFO" "Removing file: ${file}"
        rm -f "${file}"
        if [[ ! -f "${file}" ]]; then
            echo "  ✅ Removed: ${file}"
            removed_count=$((removed_count + 1))
        else
            echo "  ❌ Failed to remove: ${file}"
        fi
    fi
done

# Also remove any lock files or incomplete files
debug_log "INFO" "Cleaning up additional files"
rm -f "${CACHE_DIR}/.manual_download_lock"
rm -f "${SNAPSHOT_DIR}"/*.incomplete

# Try to remove empty directories
debug_log "INFO" "Removing empty directories if possible"
rmdir "${SNAPSHOT_DIR}" 2>/dev/null || true
rmdir "${CACHE_DIR}/snapshots" 2>/dev/null || true
rmdir "${CACHE_DIR}" 2>/dev/null || true

echo ""
if [[ $removed_count -eq ${#existing_files[@]} ]]; then
    debug_log "INFO" "All files removed successfully"
    echo "🎉 Successfully removed ${removed_count} model file(s)!"
    echo ""
    echo "✅ Model cache cleared - you can now:"
    echo "   • Run ./scripts/manual_model_download.sh to re-download"
    echo "   • Test the app's automatic download functionality"
    echo "   • Start fresh with model initialization"
else
    debug_log "ERROR" "Some files could not be removed"
    echo "⚠️  Removed ${removed_count} of ${#existing_files[@]} files"
    echo "   Some files may still exist - check permissions or try again"
fi

echo ""
echo "💡 Note: The Web app will now need to download the model again"
echo "   when AI features are first used."