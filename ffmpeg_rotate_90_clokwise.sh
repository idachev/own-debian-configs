#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IN_FILE=$1

OUT_FILE=$(echo "$IN_FILE" | sed 's/\.[^\.]*$/_90\.mp4/')

if [ "$IN_FILE" = "$OUT_FILE" ]; then
  echo "Failed to parse file extention."
  exit 1
fi

ffmpeg -i "${IN_FILE}" -vf "transpose=1" -c:a copy "${OUT_FILE}"

touch -r "${IN_FILE}" "${OUT_FILE}"

# "transpose=2,transpose=2" 180 degrees
# 0 = 90CounterCLockwise and Vertical Flip (default)
# 1 = 90Clockwise
# 2 = 90CounterClockwise
# 3 = 90Clockwise and Vertical Flip

echo -e "\nTo play:\nvlc $OUT_FILE"

