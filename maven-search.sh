#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_clipboard_content() {
    if command -v xclip &> /dev/null; then
        clipboard=$(xclip -selection clipboard -o 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$clipboard"
            return 0
        fi
    fi

    if command -v xsel &> /dev/null; then
        clipboard=$(xsel --clipboard 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$clipboard"
            return 0
        fi
    fi

    if command -v wl-paste &> /dev/null; then
        clipboard=$(wl-paste 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$clipboard"
            return 0
        fi
    fi

    echo "Error: Could not get clipboard content" >&2
    return 1
}

open_url() {
    local url="$1"

    if command -v xdg-open &> /dev/null; then
        xdg-open "$url" &> /dev/null &
    elif command -v google-chrome &> /dev/null; then
        google-chrome "$url" &> /dev/null &
    elif command -v firefox &> /dev/null; then
        firefox "$url" &> /dev/null &
    elif command -v chromium &> /dev/null; then
        chromium "$url" &> /dev/null &
    else
        echo "Error: No suitable browser found" >&2
        return 1
    fi

    return 0
}

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

maven_search_url="https://mvnrepository.com/search?q=${content}"

echo "Opening browser with URL: ${maven_search_url}"
open_url "${maven_search_url}"
