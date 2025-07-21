#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. ${DIR}/search-lib.sh

if [ -n "$1" ]; then
    content="$1"
    echo "Using provided argument: $content"
else
    clipboard_content=$(get_clipboard_content)
    if [ $? -ne 0 ]; then
        exit 1
    fi

    content=$(echo "$clipboard_content" | xargs)
    echo "Using clipboard content: $content"
fi

maven_search_url="https://www.npmjs.com/search?q=${content}"

echo "Opening browser with URL: ${maven_search_url}"
open_url "${maven_search_url}"
