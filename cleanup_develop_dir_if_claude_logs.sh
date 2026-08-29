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

# Only tmp/claude-logs. Other tmp trees hold photos, exports, sessions.
if [ "$(basename "${TARGET}")" = "claude-logs" ] && \
   [ "$(basename "$(dirname "${TARGET}")")" = "tmp" ]; then
  echo "echo"
  echo "echo \"Cleanup ${TARGET}\""
  echo "rm -rf \"${TARGET}\""
fi
