#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_ARG="${1%/}"
IMG_EXT=${2}

if [ -z "${INPUT_ARG}" ]; then
  echo "Usage: $0 <file|directory> [image ext]"
  echo ""
  echo "Supported formats: jpg, jpeg, png, tiff, tif, bmp (case insensitive)"
  echo "By default processes all supported formats. Specify ext to limit to one."
  echo ""
  echo "Environment variables:"
  echo "  WEBP_QUALITY  - WebP quality 0-100 (default: 75)"
  echo "  MAX_SIZE      - Max dimension for longer side in pixels (default: no resize)"
  echo "                  e.g., MAX_SIZE=2048 resizes so longest side is 2048px"
  echo "  STORE_HASH    - Set to 1 to store SHA512 of original in XMP metadata (requires exiftool)"
  echo "                  Useful for sync to detect already-converted files"
  echo "  PARALLEL      - Number of parallel conversions (default: 1)"
  echo ""
  echo "Required dependencies: cwebp, convert (ImageMagick), exiftool"
  echo ""
  echo "To check if a webp was converted from a specific file:"
  echo "  exiftool -XMP:OriginalDocumentID file.webp"
  exit 1
fi

if [ ! -e "${INPUT_ARG}" ]; then
  echo "Error: '${INPUT_ARG}' does not exist"
  exit 1
fi

INPUT=$(realpath "${INPUT_ARG}")

if [ -z "${WEBP_QUALITY}" ]; then
  WEBP_QUALITY=75
fi

if [ -z "${PARALLEL}" ]; then
  PARALLEL=1
fi

# Check required dependencies
command -v cwebp >/dev/null 2>&1 || \
  { echo -e "cwebp is missing, please install it using:\nsudo apt-get install webp" && exit 1; }

command -v convert >/dev/null 2>&1 || \
  { echo -e "convert (ImageMagick) is missing, please install it using:\nsudo apt-get install imagemagick" && exit 1; }

command -v exiftool >/dev/null 2>&1 || \
  { echo -e "exiftool is missing, please install it using:\nsudo apt-get install libimage-exiftool-perl" && exit 1; }

# Function to convert a single file
convert_file() {
  local file="$1"
  local dir=$(dirname "${file}")
  local ext="${file##*.}"
  local base_name=$(basename "${file}" ."${ext}")
  local temp_file="${dir}/.tmp_convert_${base_name}.${ext}"
  local output_file="${dir}/${base_name}.webp"

  echo "Processing ${file}"

  # Calculate SHA512 of original file before any processing (if requested)
  local original_hash=""
  if [ "${STORE_HASH}" = "1" ]; then
    original_hash=$(sha512sum "${file}" | cut -d' ' -f1)
  fi

  # Always create a temp copy - either resized or plain copy
  if [ -n "${MAX_SIZE}" ]; then
    # Resize so longest side is MAX_SIZE, only if image is larger (> suffix)
    # -auto-orient applies EXIF rotation
    if ! convert "${file}" -auto-orient -resize "${MAX_SIZE}x${MAX_SIZE}>" "${temp_file}"; then
      echo "Error: Failed to resize ${file}"
      rm -f "${temp_file}"
      return 1
    fi
  else
    # Just copy the original to temp
    cp "${file}" "${temp_file}"
  fi

  # Copy all EXIF from original to temp file
  exiftool -quiet -overwrite_original -TagsFromFile "${file}" -all:all "${temp_file}" 2>/dev/null

  # Store SHA512 hash in XMP metadata (will be copied to webp by cwebp)
  if [ -n "${original_hash}" ]; then
    exiftool -quiet -overwrite_original -XMP:OriginalDocumentID="sha512:${original_hash}" "${temp_file}"
  fi

  # Convert to webp with metadata preservation (EXIF, ICC, XMP)
  if cwebp -q "${WEBP_QUALITY}" -alpha_q 100 -metadata all "${temp_file}" -o "${output_file}"; then
    # Preserve original file modification timestamp
    touch -r "${file}" "${output_file}"
  else
    echo "Error: Failed to convert ${file} to webp"
    rm -f "${temp_file}"
    return 1
  fi

  # Always clean up temp file
  rm -f "${temp_file}"
}

# Wait for a job slot to become available
wait_for_slot() {
  while [ "$(jobs -rp | wc -l)" -ge "${PARALLEL}" ]; do
    sleep 0.1
  done
}

if [ -f "${INPUT}" ]; then
  # Single file mode
  convert_file "${INPUT}"
else
  # Directory mode
  # Common image formats supported by cwebp
  if [ -z "${IMG_EXT}" ]; then
    IMG_EXTENSIONS="jpg jpeg png tiff tif bmp"
  else
    IMG_EXTENSIONS="${IMG_EXT}"
  fi

  found=false
  job_count=0

  for ext in ${IMG_EXTENSIONS}; do
    # Check both lowercase and uppercase extensions
    for file in "${INPUT}"/*."${ext}" "${INPUT}"/*."${ext^^}"; do
      [ -e "${file}" ] || continue
      found=true

      if [ "${PARALLEL}" -gt 1 ]; then
        # Wait for available slot
        wait_for_slot
        # Run in background
        convert_file "${file}" &
        job_count=$((job_count + 1))
      else
        # Sequential mode
        convert_file "${file}"
      fi
    done
  done

  # Wait for all background jobs to complete
  if [ "${PARALLEL}" -gt 1 ] && [ "${job_count}" -gt 0 ]; then
    echo "Waiting for ${job_count} jobs to complete..."
    wait
    echo "All jobs completed."
  fi

  if [ "${found}" = false ]; then
    echo "No image files found in ${INPUT}"
    echo "Supported formats: ${IMG_EXTENSIONS}"
    exit 1
  fi
fi
