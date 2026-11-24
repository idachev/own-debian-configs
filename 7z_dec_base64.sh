#!/bin/bash

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s INPUT\n' "${0##*/}" >&2
    exit 2
fi

archive=$(mktemp "${TMPDIR:-/tmp}/7z_dec_base64.XXXXXXXXXX") || exit
trap 'rm -f -- "$archive"' EXIT

base64 -d < "$1" > "$archive" || exit
7z x -bb1 "$archive"
