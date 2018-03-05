#!/bin/bash

# routes for eht0 should be:
# 0.0.0.0         10.23.11.253    0.0.0.0         UG    0      0        0 eth0
# 10.23.10.0      0.0.0.0         255.255.254.0   U     0      0        0 eth0

echo -e '\nRoutes before restoring:'
sudo route -n

echo -e '\nRestoring eth0...'
sudo ifconfig eth0 up
sudo dhclient -v eth0

echo -e '\nRoutes after restoring:'
sudo route -n
