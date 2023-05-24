#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARCH_A=$1
ARCH_B=$2

TMP_DIR=$(mktemp -d --suffix="-7z-cmp")

echo -n "Do manual cleanup:\nrm -rf -- ${TMP_DIR}"

TMP_DIR_A=${TMP_DIR}/a
TMP_DIR_B=${TMP_DIR}/b

mkdir -p "${TMP_DIR_A}"
mkdir -p "${TMP_DIR_B}"

echo -n "\nExtracting ${ARCH_A} to ${TMP_DIR_A}"
7z x "${ARCH_A}" -o${TMP_DIR_A}

echo -n "\nExtracting ${ARCH_B} to ${TMP_DIR_B}"
7z x "${ARCH_B}" -o${TMP_DIR_B}

echo -n "\nComparing ${TMP_DIR_A} vs ${TMP_DIR_B}"
kdiff3 "${TMP_DIR_A}" "${TMP_DIR_B}"

echo -n "\nDo manual cleanup:\nrm -rf -- ${TMP_DIR}"
