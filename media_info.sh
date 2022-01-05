#!/bin/bash

SOURCE="$1"

if [ -z "${SOURCE}" ] ; then
  echo "Expected 1 argument the <media file>"
  exit 1
fi

exiftool -a -u -g1 "${SOURCE}"

