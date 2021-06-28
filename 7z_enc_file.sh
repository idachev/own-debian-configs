#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TO_ARCHIVE=$1
"${DIR}/7z_enc.sh" "${TO_ARCHIVE}".7z "${TO_ARCHIVE}"
