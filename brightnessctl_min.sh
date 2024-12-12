#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

brightnessctl set 1

# Replaced by f.lux
# brightness-controller &

PID=$(echo $!)

sleep 1

if [[ -n ${PID} ]]; then
  kill $(pgrep -P ${PID})
fi


${DIR}/brightnessctl_show.sh &

