#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTENT=$(xclip -selection clipboard -o)

if [ -z "${CONTENT}" ]; then
    echo "No content found in clipboard"
    exit 1
fi

echo "=== Clipboard Content (first 100 chars) ==="
echo "${CONTENT}" | command head -n 1 | cut -c1-100
echo "..."
echo ""
echo "=== Base64 Decoded + Zip Decompressed ==="
echo -n "${CONTENT}" | base64 -d | python3 -c "
import sys, zlib, gzip, io
data = sys.stdin.buffer.read()
for name, fn in [
    ('zlib', lambda d: zlib.decompress(d)),
    ('raw deflate', lambda d: zlib.decompress(d, -zlib.MAX_WBITS)),
    ('gzip', lambda d: gzip.decompress(d)),
    ('zlib auto', lambda d: zlib.decompress(d, zlib.MAX_WBITS | 32)),
]:
    try:
        sys.stdout.buffer.write(fn(data))
        sys.exit(0)
    except Exception:
        pass
print('Error: could not decompress data with zlib, raw deflate, or gzip', file=sys.stderr)
sys.exit(1)
"
echo ""
