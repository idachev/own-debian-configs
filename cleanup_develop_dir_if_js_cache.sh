#!/bin/bash
[ "$1" = -x ] && shift && set -x

TARGET=$1

if [ ! -d "${TARGET}" ]; then
  if [ -z "${TARGET}" ]; then
    exit 2
  fi

  echo -e "\nExpecting valid directory: ${TARGET}"
  exit 1
fi

NAME=$(basename "${TARGET}")
BASE_DIR=$(dirname "${TARGET}")

has_pkg() { [ -s "${BASE_DIR}/package.json" ]; }
has_nx() { [ -s "${BASE_DIR}/nx.json" ]; }
has_next_cfg() {
  [ -s "${BASE_DIR}/next.config.js" ] || \
    [ -s "${BASE_DIR}/next.config.mjs" ] || \
    [ -s "${BASE_DIR}/next.config.ts" ] || \
    [ -s "${BASE_DIR}/next.config.cjs" ]
}
has_open_next_cfg() {
  [ -s "${BASE_DIR}/open-next.config.ts" ] || \
    [ -s "${BASE_DIR}/open-next.config.js" ] || \
    [ -s "${BASE_DIR}/open-next.config.mjs" ]
}

case "${NAME}" in
  .next)
    if has_pkg || has_next_cfg; then
      echo "echo"
      echo "echo \"Cleanup ${TARGET}\""
      echo "rm -rf \"${TARGET}\""
    fi
    ;;
  .open-next)
    if has_pkg || has_open_next_cfg || has_next_cfg; then
      echo "echo"
      echo "echo \"Cleanup ${TARGET}\""
      echo "rm -rf \"${TARGET}\""
    fi
    ;;
  .turbo|.parcel-cache)
    if has_pkg; then
      echo "echo"
      echo "echo \"Cleanup ${TARGET}\""
      echo "rm -rf \"${TARGET}\""
    fi
    ;;
  .nx)
    if has_nx || has_pkg; then
      echo "echo"
      echo "echo \"Cleanup ${TARGET}\""
      echo "rm -rf \"${TARGET}\""
    fi
    ;;
esac
