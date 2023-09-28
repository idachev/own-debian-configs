#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

brightnessctl set 1

# Replaced by f.lux
# brightness-controller &

PID=$(echo $!)

sleep 1

kill $(pgrep -P ${PID})


${DIR}/brightnessctl_show.sh &

