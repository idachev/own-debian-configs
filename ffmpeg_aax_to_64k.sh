#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Audible aax
BIT_RATE='64k'
SAMPLE_RATE=22050

ffmpeg_to_mp3.sh --bit_rate=${BIT_RATE} --sample_rate=${SAMPLE_RATE} $@
