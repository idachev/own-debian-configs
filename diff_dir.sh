#/bin/bash

SRC_DIR=$1
DST_DIR=$2

if [ ! -d "${SRC_DIR}" ]; then
  echo "\nExpect existing source dir: ${SRC_DIR}"
  exit 1
fi

if [ ! -d "${DST_DIR}" ]; then
  echo "\nExpect existing destination dir: ${DST_DIR}"
  exit 1
fi

EXCLUDE_PATTERN='*.log'

diff --no-dereference --brief --recursive --exclude "${EXCLUDE_PATTERN}" \
 "${SRC_DIR}" "${DST_DIR}"

