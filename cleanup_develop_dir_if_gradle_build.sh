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

# Only Gradle module output. A Java package named build, CMake build/,
# docker/build with Dockerfiles, or scripts/build must not match.
if [ "$(basename "${TARGET}")" != "build" ]; then
  exit 0
fi

BASE_DIR=$(dirname "${TARGET}")

if [ -s "${BASE_DIR}/build.gradle" ] || \
   [ -s "${BASE_DIR}/build.gradle.kts" ] || \
   [ -s "${BASE_DIR}/settings.gradle" ] || \
   [ -s "${BASE_DIR}/settings.gradle.kts" ]; then
  echo "echo"
  echo "echo \"Cleanup ${TARGET}\""
  echo "rm -rf \"${TARGET}\""
fi
