#!/bin/bash

echo -e "\nBefore"
sudo route -n

route -n | awk -F ' ' '{print $8}' | grep 'br-' | \
  xargs -I{} sudo ifconfig "{}" down

echo -e "\nAfter"
sudo route -n

