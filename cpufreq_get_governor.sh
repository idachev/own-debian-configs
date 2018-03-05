#!/bin/bash

nump=$(nproc)

for i in $(seq 0 $((nump-1)))
do
  echo Get CPU: $i
  cpufreq-info -m -p -c $i
done

