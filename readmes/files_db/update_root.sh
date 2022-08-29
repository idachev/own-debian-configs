#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_DIR=$(realpath $1)

if [ ! -d "${TARGET_DIR}" ]; then
  echo "Should pass a directory, exit!"
  exit 1
fi

cd "${DIR}/.."

files_db.py -t 1 -root . "${TARGET_DIR}"

