#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

brightnessctl set 3500

brightness-reset

${DIR}/brightnessctl_show.sh &

