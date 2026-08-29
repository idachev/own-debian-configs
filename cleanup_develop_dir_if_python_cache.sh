#!/bin/bash
[ "$1" = -x ] && shift && set -x

TARGET=$1

if [ ! -d "${TARGET}" ]; then
  if [ -z "${TARGET}" ]; then
    exit 2
  fi

  echo -e "\nExpecting valid directory: ${TARGET}" >&2
  exit 1
fi

NAME=$(basename "${TARGET}")

case "${NAME}" in
  __pycache__|.pytest_cache|.mypy_cache|.ruff_cache)
    echo "echo"
    echo "echo \"Cleanup ${TARGET}\""
    echo "rm -rf \"${TARGET}\""
    ;;
  htmlcov)
    if [ -s "${TARGET}/index.html" ]; then
      echo "echo"
      echo "echo \"Cleanup ${TARGET}\""
      echo "rm -rf \"${TARGET}\""
    fi
    ;;
esac
