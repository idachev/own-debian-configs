#!/bin/bash

NET_PREFIX="10.23.10"

for i in $(seq 1 255); do
  ip="$NET_PREFIX.$i"
  echo $ip
  ssh $ip 'echo 1'
done


