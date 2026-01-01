#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(realpath "${1%/}" 2>/dev/null)
IMG_EXT=${2}

if [ -z "${INPUT}" ] || [ ! -e "${INPUT}" ]; then
  echo "Usage: $0 <file|directory> [image ext - default: jpg]"
  exit 1
fi

if [ -z "${WEBP_QUALITY}" ]; then
  WEBP_QUALITY=75
fi

command -v cwebp >/dev/null 2>&1 || \
 { echo -e "cwebp is missing, please install it using:\nsudo apt-get install webp" && exit 1; }

# Function to convert a single file
convert_file() {
  local file="$1"
  local dir=$(dirname "${file}")
  local ext="${file##*.}"
  local base_name=$(basename "${file}" ."${ext}")

  echo "Processing ${file}"
  cwebp -q "${WEBP_QUALITY}" -alpha_q 100 "${file}" -o "${dir}/${base_name}.webp"
}

if [ -f "${INPUT}" ]; then
  # Single file mode
  convert_file "${INPUT}"
else
  # Directory mode
  if [ -z "${IMG_EXT}" ]; then
    IMG_EXT="jpg"
  fi

  found=false
  for file in "${INPUT}"/*."${IMG_EXT}"; do
    [ -e "${file}" ] || continue
    found=true
    convert_file "${file}"
  done

  if [ "${found}" = false ]; then
    echo "No files found ${INPUT}/*.${IMG_EXT}"
    exit 1
  fi
fi
