#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

currentBrightness=$(brightnessctl g)
maxBrightness=$(brightnessctl m)

scale=1000
if (( ${currentBrightness} < ${maxBrightness}/50 )); then
  scale=100
elif (( ${currentBrightness} < ${maxBrightness}/20 )); then
  scale=250
elif (( ${currentBrightness} < ${maxBrightness}/10 )); then
  scale=500
fi

brightnessctl set +${scale}

yad --no-buttons --borders 30 --timeout 1 --text-align center --on-top --undecorated \
  --text "<span size=\"x-large\" color=\"#000000\">Brightness\n<b>$(cat /sys/class/backlight/intel_backlight/brightness)</b></span>" &
