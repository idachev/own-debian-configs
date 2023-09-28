#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

brightnessctl set 3500

# Replaced by f.lux
# brightness-reset

${DIR}/brightnessctl_show.sh &

