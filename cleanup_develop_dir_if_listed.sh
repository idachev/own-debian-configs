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

git_tracks_target() {
  command git -C "${TARGET}" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
    command git -C "${TARGET}" ls-files -- . | command grep -q .
}

emit_cleanup() {
  echo "echo"
  echo "echo \"Cleanup ${TARGET}\""
  echo "rm -rf \"${TARGET}\""
}

if git_tracks_target; then
  exit 0
fi

case "${NAME}" in
  coverage)
    if [ -s "${BASE_DIR}/package.json" ] && {
      [ -s "${TARGET}/lcov.info" ] || \
        [ -s "${TARGET}/index.html" ] || \
        [ -s "${TARGET}/coverage-final.json" ] || \
        [ -s "${TARGET}/clover.xml" ] || \
        [ -d "${TARGET}/lcov-report" ]
    }; then
      emit_cleanup
    fi
    ;;
  storybook-static)
    if [ -s "${BASE_DIR}/package.json" ] && [ -s "${TARGET}/index.html" ]; then
      emit_cleanup
    fi
    ;;
  .vite)
    if [ -s "${BASE_DIR}/package.json" ]; then
      emit_cleanup
    fi
    ;;
  *)
    emit_cleanup
    ;;
esac
