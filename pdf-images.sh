#!/usr/bin/env bash
# Extract original image sizes from PDF pages using pdfimages (poppler-utils)

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: pdf-images.sh <file.pdf> [file2.pdf ...]"
    exit 1
fi

for pdf in "$@"; do
    if [ ! -f "$pdf" ]; then
        echo "Error: '$pdf' not found" >&2
        continue
    fi

    if [ $# -gt 1 ]; then
        echo "=== $pdf ==="
    fi

    pdfimages -list "$pdf"

    if [ $# -gt 1 ]; then
        echo
    fi
done
