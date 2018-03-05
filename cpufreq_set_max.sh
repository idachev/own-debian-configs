#!/bin/bash

nump=$(nproc)

maxf=$1

if [ "${maxf}" == ""  ]; then
  maxf=1700000
fi

for i in $(seq 0 $((nump-1)))
do
  sudo cpufreq-set -c $i -r --max "${maxf}"
  echo Set CPU: $i
  cpufreq-info -m -p -c $i
done

