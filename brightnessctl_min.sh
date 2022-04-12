#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

brightnessctl set 1

brightness-controller &

PID=$(echo $!)

sleep 1

kill $(pgrep -P ${PID})

yad --no-buttons --borders 30 --timeout 1 --text-align center \
  --on-top --undecorated --skip-taskbar --sticky \
  --text "<span size=\"x-large\">Brightness\n<b>$(cat /sys/class/backlight/intel_backlight/brightness)</b></span>" &
