#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_ARG="${1}"
ROTATION=${2}

show_usage() {
  echo "Usage: $0 <file.webp> <degrees>"
  echo ""
  echo "Degrees: 90, 180, 270 (clockwise)"
  echo ""
  echo "Environment variables:"
  echo "  WEBP_QUALITY  - WebP quality 0-100 (default: 75)"
  echo ""
  echo "Required dependencies: cwebp, convert (ImageMagick), exiftool"
  echo ""
  echo "Preserves EXIF metadata and file modification timestamp."
  exit 1
}

if [ -z "${INPUT_ARG}" ] || [ -z "${ROTATION}" ]; then
  show_usage
fi

if [ ! -e "${INPUT_ARG}" ]; then
  echo "Error: '${INPUT_ARG}' does not exist"
  exit 1
fi

if [ ! -f "${INPUT_ARG}" ]; then
  echo "Error: '${INPUT_ARG}' is not a file"
  exit 1
fi

INPUT=$(realpath "${INPUT_ARG}")

# Validate rotation
case "${ROTATION}" in
  90|180|270) ;;
  *)
    echo "Error: Rotation must be 90, 180, or 270 degrees"
    exit 1
    ;;
esac

# Validate file extension
ext="${INPUT##*.}"
ext_lower=$(echo "${ext}" | tr '[:upper:]' '[:lower:]')
if [ "${ext_lower}" != "webp" ]; then
  echo "Error: File must be a .webp file"
  exit 1
fi

if [ -z "${WEBP_QUALITY}" ]; then
  WEBP_QUALITY=75
fi

# Check required dependencies
command -v cwebp >/dev/null 2>&1 || \
  { echo -e "cwebp is missing, please install it using:\nsudo apt-get install webp" && exit 1; }

command -v convert >/dev/null 2>&1 || \
  { echo -e "convert (ImageMagick) is missing, please install it using:\nsudo apt-get install imagemagick" && exit 1; }

command -v exiftool >/dev/null 2>&1 || \
  { echo -e "exiftool is missing, please install it using:\nsudo apt-get install libimage-exiftool-perl" && exit 1; }

# Create temp files (use JPEG as intermediate - it fully supports EXIF unlike PNG)
dir=$(dirname "${INPUT}")
base_name=$(basename "${INPUT}" .webp)
temp_jpg="${dir}/.tmp_rotate_${base_name}.jpg"
temp_webp="${dir}/.tmp_rotate_${base_name}.webp"

# Cleanup function
cleanup() {
  rm -f "${temp_jpg}" "${temp_webp}"
}
trap cleanup EXIT

echo "Rotating ${INPUT} by ${ROTATION} degrees..."

# Convert webp to JPEG (JPEG supports EXIF properly, PNG doesn't)
if ! convert "${INPUT}" -quality 100 "${temp_jpg}"; then
  echo "Error: Failed to decode webp"
  exit 1
fi

# Copy EXIF from original webp to JPEG
exiftool -quiet -overwrite_original -TagsFromFile "${INPUT}" -all:all "${temp_jpg}" 2>/dev/null

# Rotate the JPEG
if ! convert "${temp_jpg}" -rotate "${ROTATION}" "${temp_jpg}"; then
  echo "Error: Failed to rotate image"
  exit 1
fi

# Fix EXIF orientation tag after rotation (reset to normal since pixels are now rotated)
exiftool -quiet -overwrite_original -Orientation=1 -n "${temp_jpg}" 2>/dev/null

# Re-encode to webp with metadata
if ! cwebp -q "${WEBP_QUALITY}" -metadata all "${temp_jpg}" -o "${temp_webp}"; then
  echo "Error: Failed to encode webp"
  exit 1
fi

# Preserve original file modification timestamp
touch -r "${INPUT}" "${temp_webp}"

# Replace original with rotated version
mv "${temp_webp}" "${INPUT}"

echo "Done: ${INPUT}"
