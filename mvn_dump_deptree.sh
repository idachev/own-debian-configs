#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_DIR=$(realpath "./")
for iter in ${CURRENT_DIR}/*; do
  if [[ -d "${iter}" ]] && [[ -f "${iter}/pom.xml"  ]]; then
    cd "${iter}"
    ITER_BASE_NAME=$(basename "${iter}")
    echo -e "\nDump dependency tree for ${ITER_BASE_NAME}"
    mvn dependency:tree > "${CURRENT_DIR}/${ITER_BASE_NAME}_dependency_tree.txt" 2>&1
  fi
done
