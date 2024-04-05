#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${DIR}/.."

files_db.py -t 2 -db .

