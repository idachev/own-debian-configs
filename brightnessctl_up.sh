#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

currentBrightness=$(brightnessctl g)
maxBrightness=$(brightnessctl m)

scale=1000
if (( ${currentBrightness} < ${maxBrightness}/100 )); then
  scale=10
elif (( ${currentBrightness} < ${maxBrightness}/50 )); then
  scale=50
elif (( ${currentBrightness} < ${maxBrightness}/20 )); then
  scale=100
elif (( ${currentBrightness} < ${maxBrightness}/10 )); then
  scale=250
fi

brightnessctl set +${scale}

${DIR}/brightnessctl_show.sh &

