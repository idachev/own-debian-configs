#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

brightnessctl set +10

zenity --width 300 --notification \
  --text "Brightness level: $(cat /sys/class/backlight/intel_backlight/brightness)" --timeout 1 &
