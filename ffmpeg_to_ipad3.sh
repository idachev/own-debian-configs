#!/bin/bash

for i in "$@"; do
  OUT_NAME=$(echo "$i" | sed 's/\.[^.]\{0,\}$//')

  ffmpeg -i "$i" -acodec aac -c:a libfdk_aac -ac 2 -strict experimental -ab 160k -vcodec libx264 -preset slow -profile:v baseline -level 30 -maxrate 10000000 -bufsize 10000000 -b 1500k -f mp4 -threads 0 "$OUT_NAME.mp4"
done
