#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTENT=$(xclip -selection clipboard -o)

if [ -z "${CONTENT}" ]; then
    echo "No content found in clipboard"
    exit 1
fi

echo "=== Clipboard Content ==="
echo "${CONTENT}"
echo ""
echo "=== Base64 Decoded ==="
echo -n "${CONTENT}" | base64 -d
echo ""
