#!/bin/bash

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s INPUT\n' "${0##*/}" >&2
    exit 2
fi

output=${1}_enc
if [ -d "$output" ]; then
    printf 'Output is a directory: %s\n' "$output" >&2
    exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/7z_enc_base64.XXXXXXXXXX") || exit
archive=$scratch/archive.7z
encoded=
cleanup() {
    if [ -n "$encoded" ]; then
        rm -f -- "$encoded"
    fi
    rm -f -- "$archive"
    rmdir -- "$scratch"
}
trap cleanup EXIT

7z_enc.sh "$archive" -spd -- "$1" || exit

output_dir=.
if [[ $output == */* ]]; then
    output_dir=${output%/*}
fi
encoded=$(mktemp -- "$output_dir/.7z_enc_base64.XXXXXXXXXX") || exit
base64 < "$archive" > "$encoded" || exit
mv -f -- "$encoded" "$output" || exit

printf 'Generated: %s\n' "$output"
