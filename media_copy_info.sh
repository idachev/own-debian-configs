#!/bin/bash

SOURCE="$1"
TARGET="$2"

if [ -z "${SOURCE}" ] || [ -z "${TARGET}" ]; then
  echo "Expected 2 arguments the <source media file> <target media file>"
  exit 1
fi

set -e

exiftool -TagsFromFile "${SOURCE}" "-all:all>all:all" "${TARGET}"

exiftool "-FileModifyDate<CreateDate" "${TARGET}"

rm "${TARGET}_original"

