#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EPOCH_TIME=$(xclip -selection clipboard -o)

if [ ${#EPOCH_TIME} -ge 13 ]; then
    EPOCH_TIME=$(($EPOCH_TIME/1000))
fi

date -d @$EPOCH_TIME
