#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_ARG="${1%/}"

if [ -z "${INPUT_ARG}" ]; then
  echo "Usage: $0 <directory>"
  echo ""
  echo "Safely moves original image files to ./for-cleanup if:"
  echo "  1. A .webp file with same name exists"
  echo "  2. SHA512 hash of original matches XMP:OriginalDocumentID in webp"
  echo ""
  echo "Supported formats: jpg, jpeg, png, tiff, tif, bmp (case insensitive)"
  echo ""
  echo "Environment variables:"
  echo "  DRY_RUN       - Set to 1 to only show what would be moved (default: 0)"
  echo ""
  echo "Required dependencies: exiftool"
  exit 1
fi

if [ ! -e "${INPUT_ARG}" ]; then
  echo "Error: '${INPUT_ARG}' does not exist"
  exit 1
fi

if [ ! -d "${INPUT_ARG}" ]; then
  echo "Error: '${INPUT_ARG}' is not a directory"
  exit 1
fi

INPUT=$(realpath "${INPUT_ARG}")

if [ -z "${DRY_RUN}" ]; then
  DRY_RUN=0
fi

# Check required dependencies
command -v exiftool >/dev/null 2>&1 || \
  { echo -e "exiftool is missing, please install it using:\nsudo apt-get install libimage-exiftool-perl" && exit 1; }

# Cleanup directory
CLEANUP_DIR="${INPUT}/for-cleanup"

# Supported image extensions
IMG_EXTENSIONS="jpg jpeg png tiff tif bmp"

# Counters
moved_count=0
skipped_no_webp=0
skipped_no_hash=0
skipped_hash_mismatch=0
error_count=0

# Function to check and move a single file
check_and_move_file() {
  local file="$1"
  local dir=$(dirname "${file}")
  local ext="${file##*.}"
  local base_name=$(basename "${file}" ."${ext}")
  local webp_file="${dir}/${base_name}.webp"

  # Check if webp exists
  if [ ! -f "${webp_file}" ]; then
    ((skipped_no_webp++))
    return 0
  fi

  # Get hash from webp
  local webp_hash=$(exiftool -s -s -s -XMP:OriginalDocumentID "${webp_file}" 2>/dev/null)

  # Check if hash exists in webp
  if [ -z "${webp_hash}" ]; then
    echo "Skipping ${file}: No hash stored in ${webp_file}"
    ((skipped_no_hash++))
    return 0
  fi

  # Remove sha512: prefix if present
  webp_hash="${webp_hash#sha512:}"

  # Calculate hash of original file
  local original_hash=$(sha512sum "${file}" | cut -d' ' -f1)

  # Compare hashes
  if [ "${original_hash}" != "${webp_hash}" ]; then
    echo "Skipping ${file}: Hash mismatch"
    echo "  Original: ${original_hash:0:16}..."
    echo "  WebP:     ${webp_hash:0:16}..."
    ((skipped_hash_mismatch++))
    return 0
  fi

  # Hashes match - move to cleanup directory
  if [ "${DRY_RUN}" = "1" ]; then
    echo "[DRY RUN] Would move: ${file}"
    ((moved_count++))
  else
    # Create cleanup directory if needed
    if [ ! -d "${CLEANUP_DIR}" ]; then
      mkdir -p "${CLEANUP_DIR}"
    fi

    # Preserve subdirectory structure relative to INPUT
    local rel_path="${file#${INPUT}/}"
    local rel_dir=$(dirname "${rel_path}")
    local target_dir="${CLEANUP_DIR}"

    if [ "${rel_dir}" != "." ]; then
      target_dir="${CLEANUP_DIR}/${rel_dir}"
      mkdir -p "${target_dir}"
    fi

    if mv "${file}" "${target_dir}/"; then
      echo "Moved: ${file}"
      ((moved_count++))
    else
      echo "Error: Failed to move ${file}"
      ((error_count++))
    fi
  fi
}

echo "Scanning ${INPUT} for converted media files..."
if [ "${DRY_RUN}" = "1" ]; then
  echo "(DRY RUN mode - no files will be moved)"
fi
echo ""

# Find and process all image files
found=false
for ext in ${IMG_EXTENSIONS}; do
  # Check both lowercase and uppercase extensions
  for file in "${INPUT}"/*."${ext}" "${INPUT}"/*."${ext^^}"; do
    [ -e "${file}" ] || continue
    found=true
    check_and_move_file "${file}"
  done
done

if [ "${found}" = false ]; then
  echo "No image files found in ${INPUT}"
  echo "Supported formats: ${IMG_EXTENSIONS}"
  exit 1
fi

# Print summary
echo ""
echo "=== Summary ==="
echo "Moved to for-cleanup:    ${moved_count}"
echo "Skipped (no webp):       ${skipped_no_webp}"
echo "Skipped (no hash):       ${skipped_no_hash}"
echo "Skipped (hash mismatch): ${skipped_hash_mismatch}"
if [ "${error_count}" -gt 0 ]; then
  echo "Errors:                  ${error_count}"
fi

if [ "${DRY_RUN}" = "1" ] && [ "${moved_count}" -gt 0 ]; then
  echo ""
  echo "Run without DRY_RUN=1 to actually move files."
fi
