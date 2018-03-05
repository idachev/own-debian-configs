#!/bin/sh

LOOK_FOR="$1"

for i in `find . -xdev -type f -name '*jar' -o -iname '*zip'`
do
  unzip -l "$i" | grep --color -n -T -i "$LOOK_FOR"
  if [ $? -eq 0 ]; then
    echo "Found in $i"
    echo
  fi
done

