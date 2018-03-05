#!/bin/bash

IN_FILE=$1

OUT_FILE=$(echo "$IN_FILE" | sed 's/\.[^\.]*$/\.mpg/')

if [ "$IN_FILE" = "$OUT_FILE" ]; then
  echo "Failed to parse file extention."
  exit 1
fi

CODEC=x264

mencoder -ovc $CODEC -v -oac faac "$IN_FILE" -o "$OUT_FILE"

echo -e "\nTo play:\nvlc $OUT_FILE"

