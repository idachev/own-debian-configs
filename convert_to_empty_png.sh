#!/bin/bash

for var in "$@"; do
  IMG_SIZE=$(convert "$var" -print "%wx%h" /dev/null)
  convert -size $IMG_SIZE xc:transparent "$var"
  echo "empty: $var"
done


