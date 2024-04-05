#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for i in "$@"; do
  OUT_NAME=$(echo "$i" | sed 's/\.[^.]\{0,\}$//')
  OUT_FILE="${OUT_NAME}_h2.mp4"

  ffmpeg -i "$i" -vf "scale=iw/2:ih/2" "${OUT_FILE}"

  touch -r "$i" "${OUT_FILE}"
done
