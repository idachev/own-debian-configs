#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_DIR=$1

if [ ! -d "${TARGET_DIR}" ]; then
  echo -e "Expecting valid dir: ${TARGET_DIR}"
  exit 1
fi

cd "${TARGET_DIR}"

find . -type d -name target -print0 | \
  xargs -0 -l1 "${DIR}/cleanup_develop_dir_if_maven_target.sh"

find . -type d -name node_modules -print0 | \
  xargs -0 -l1 "${DIR}/cleanup_develop_dir_if_npm_modules.sh"

find . -type d -name venv -print0 | \
  xargs -0 -l1 "${DIR}/cleanup_develop_dir_if_venv.sh"

find . -type d -name .gradle -print0 | \
  xargs -0 -l1 "${DIR}/cleanup_develop_dir_if_gradle.sh"
