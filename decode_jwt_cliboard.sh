#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

JWT=$(xclip -selection clipboard -o)

if [ -z "${JWT}" ]; then
    echo "No JWT found in clipboard"
    exit 1
fi

echo "${JWT}" | awk -F. '{print $2}' | base64 -d 2>/dev/null | jq --color-output
