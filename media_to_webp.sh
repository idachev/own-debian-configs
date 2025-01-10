#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SEL_DIR=$(realpath ${1%/})
IMG_EXT=${2}

if [ -z "${SEL_DIR}" ] || [ ! -d "${SEL_DIR}" ]; then
  echo "Usage: $0 <directory> [image ext - default: jpg]"
  exit 1
fi

if [ -z "${IMG_EXT}" ]; then
  IMG_EXT="jpg"
fi

if [ -z "${WEBP_QUALITY}" ]; then
  WEBP_QUALITY=75
fi

command -v cwebp >/dev/null 2>&1 || \
 { echo -e "cwebp is missing, please install it using:\nsudo apt-get install webp" && exit 1; }

for file in "${SEL_DIR}"/*."${IMG_EXT}"; do
  [ -e "${file}" ] || { echo "No files found ${SEL_DIR}/*.${IMG_EXT}"; exit 1; }

  base_name=$(basename "${file}" ."${IMG_EXT}")

  echo "Processing ${file}"

  cwebp -q "${WEBP_QUALITY}" "${file}" -o "${SEL_DIR}/${base_name}.webp"
done
