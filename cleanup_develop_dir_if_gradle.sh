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

BASE_DIR=$(dirname "${TARGET}")

# Project cache has vcs-1 / buildOutputCleanup. User-cache copies have vcsWorkingDirs.
if [ -d "${TARGET}/vcs-1" ] || \
   [ -d "${TARGET}/vcsWorkingDirs" ] || \
   [ -d "${TARGET}/buildOutputCleanup" ] || \
   [ -s "${BASE_DIR}/build.gradle" ] || \
   [ -s "${BASE_DIR}/build.gradle.kts" ] || \
   [ -s "${BASE_DIR}/settings.gradle" ] || \
   [ -s "${BASE_DIR}/settings.gradle.kts" ]; then
  echo "echo"
  echo "echo \"Cleanup ${TARGET}\""
  echo "rm -rf \"${TARGET}\""
fi
