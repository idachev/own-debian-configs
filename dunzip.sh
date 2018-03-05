#!/bin/bash
#set -v

for i in $@; do
  NAME="$i"

  TO_DIR="${NAME%.*}"

  echo -e "\n\n$i to $TO_DIR\n"
  unzip "$i" -d "$TO_DIR"
done

