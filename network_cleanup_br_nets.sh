#!/bin/bash

echo -e "\nBefore"
sudo route -n

sudo ifconfig br-9e937bbda099 down
sudo ifconfig br-4103498a9c96 down
sudo ifconfig br-6cc51567be89 down
sudo ifconfig br-e2b737621188 down
sudo ifconfig br-d0fdb5c8a2a8 down

echo -e "\nAfter"
sudo route -n

