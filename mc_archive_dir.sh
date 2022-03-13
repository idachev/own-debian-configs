#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -e

TO_ARCHIVE=$(realpath "$1")
ARCHIVE_DIR=$(dirname "${TO_ARCHIVE}")
SOURCE_NAME=$(basename "${TO_ARCHIVE}")

DATE_LAST_FILE=$(\
  find "${TO_ARCHIVE}" -type f ! -path '*/.idea/*' ! -path '*/.git/index*' ! -path '*/.git/logs*' ! -path '*/.git/refs*' -print0 | \
  ifne xargs -0 stat -c '%y' | \
  awk '{print $1}' | \
  sort -n | \
  tail -n 1 | \
  sed 's/-//g')

ARCHIVE_NAME=${SOURCE_NAME// /_}_${DATE_LAST_FILE}.tgz
DST_ARCHIVE="${ARCHIVE_DIR}/${ARCHIVE_NAME}"

echo -e "\nConfirm archive\n\tsrc: ${TO_ARCHIVE}\n\tdst: ${DST_ARCHIVE}\n"

echo -e "\nArchiving..."
tar -cf "${DST_ARCHIVE}" -I 'pigz -9' -C "${ARCHIVE_DIR}" "${SOURCE_NAME}"

echo -e "\nTesting..."
tar tf "${DST_ARCHIVE}"

echo -e "\nArchive completed: ${DST_ARCHIVE}"
