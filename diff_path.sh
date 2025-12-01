#!/bin/bash

SRC_PATH=$1
DST_PATH=$2

if [ -d "${SRC_PATH}" ] || [ -f "${SRC_PATH}" ]; then
  if [ -d "${SRC_PATH}" ]; then
    if [ ! -d "${DST_PATH}" ]; then
      >&2 echo "\nExpect existing destination dir: ${DST_PATH}"
      exit 1
    fi
  else
    if [ ! -f "${DST_PATH}" ]; then
      >&2 echo "\nExpect existing destination file: ${DST_PATH}"
      exit 1
    fi    
  fi
else
  >&2 echo "\nExpect existing source dir/file: ${SRC_PATH}"
  exit 1
fi

if [ $(realpath "${SRC_PATH}") = $(realpath "${DST_PATH}") ]; then
  >&2 echo "\nCompare same source/destination:\n\
SRC_PATH: ${SRC_PATH}\n\
DST_PATH: ${DST_PATH}\n\
REALPATH: $(realpath ${SRC_PATH})"
  exit 1 
fi


EXCLUDE_PATTERN='*.log'

echo "\nCompare ${SRC_PATH} -> ${DST_PATH}"

diff --no-dereference --brief --recursive --exclude "${EXCLUDE_PATTERN}" \
 "${SRC_PATH}" "${DST_PATH}"

