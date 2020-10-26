#!/bin/bash

for i in {1..6}; do

  OUT=$(dropbox stop)

  echo "${OUT}"

  echo "${OUT}" | grep -iq "Dropbox isn't running!"
  if [ $? -eq 0 ]; then
    break
  fi

  sleep 15
done

dropbox start

sleep 1

cpunice.sh dropbox 2 40 5

