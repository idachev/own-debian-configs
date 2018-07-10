#!/bin/bash
#set -v

for i in $@; do
  NAME="$i"

  TO_DIR="${NAME%.*}"

  echo -e "\n\n$i to $TO_DIR\n"
  7z x -o"$TO_DIR" "$i"
done

