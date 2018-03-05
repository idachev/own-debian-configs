#!/bin/bash

nump=$(nproc)

governor=$1

if [ "${governor}" == ""  ]; then
  governor="powersave"
fi

for i in $(seq 0 $((nump-1)))
do
  sudo cpufreq-set -c $i -g "${governor}"
  echo Set CPU: $i
  cpufreq-info -m -p -c $i
done

