#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET=$1

if [ ! -d "${TARGET}" ]; then
  if [ -z "${TARGET}" ]; then
    exit 2
  fi

  echo -e "\nExpecting valid directory: ${TARGET}"
  exit 1
fi

BASE_DIR=$(dirname ${TARGET})

if [ -s "${BASE_DIR}/package.json" ]; then
  echo "echo"
  echo "echo \"Cleanup ${TARGET}\""
  echo "rm -rf \"${TARGET}\""
fi
