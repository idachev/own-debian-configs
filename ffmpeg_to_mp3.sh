#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Audible aax
BIT_RATE='64k'
CHANNELS=2
SAMPLE_RATE=22050

#OVERWRITE_OUT=-y
#STRIP_INPUT='-ss 00:00:55'

while true; do
  if [ "${1}" = "--mono" ]; then
    CHANNELS=1
  elif [[ "${1}" = --bit_rate=*k ]]; then
    BIT_RATE=$(echo "${1}" | sed 's/--bit_rate=\([0-9]*\)k/\1k/')
  elif [[ "${1}" = --sample_rate=* ]]; then
    SAMPLE_RATE=$(echo "${1}" | sed 's/--sample_rate=\([0-9]*\)/\1/')
  else
    break
  fi
  shift
done

for i in "$@"; do
  IN_NAME="${i}"
  OUT_NAME_PREFIX=$(echo "$IN_NAME" | sed 's/\.[^.]\{0,\}$//')
  OUT_NAME="${OUT_NAME_PREFIX}_${BIT_RATE}.mp3"

  echo -e "\n\n================================================================================"
  echo "in: $IN_NAME"
  echo "out: $OUT_NAME"
  echo "channels: $CHANNELS"
  echo "smaple_rate: $SAMPLE_RATE"
  echo -e "bit_rate: $BIT_RATE\n"
  ffmpeg $OVERWRITE_OUT $STRIP_INPUT -i "$IN_NAME" -threads auto -ac $CHANNELS -ar $SAMPLE_RATE -ab $BIT_RATE "$OUT_NAME"

  touch -r "$IN_NAME" "$OUT_NAME"
done

