#!/bin/bash

sudo ifconfig eth0 down
sudo ifconfig eth0 hw ether 00:22:B0:A1:9A:6B
sudo ifconfig eth0 up                        

