#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SEL_DIR=$(realpath ${1%/})
IMG_EXT=${2}

if [ -z "${SEL_DIR}" ] || [ ! -d "${SEL_DIR}" ]; then
  echo "Usage: $0 <directory> <image ext>"
  exit 1
fi

if [ -z "${IMG_EXT}" ]; then
  IMG_EXT="jpg"
fi

command -v sqip >/dev/null 2>&1 || \
 { echo -e "sqip is missing, please install it using:\nnpm install -g sqip" && exit 1; }

for file in "${SEL_DIR}"/*."${IMG_EXT}"; do
  [ -e "$file" ] || { echo "No files found ${SEL_DIR}/*.${IMG_EXT}"; exit 1; }

  base_name=$(basename "$file" ."${IMG_EXT}")

  echo "Processing ${file}"

  sqip "$file" -o "${SEL_DIR}/${base_name}-lqip.svg"
done
