#!/bin/bash

mkdir /tmp/shutter
cd /tmp/shutter

wget -q \
  https://launchpad.net/ubuntu/+archive/primary/+files/libgoocanvas-common_1.0.0-1_all.deb \
  https://launchpad.net/ubuntu/+archive/primary/+files/libgoocanvas3_1.0.0-1_amd64.deb \
  https://launchpad.net/ubuntu/+archive/primary/+files/libgoo-canvas-perl_0.06-2ubuntu3_amd64.deb
        
sudo dpkg -i *.deb

sudo apt install -f -y

sudo killall shutter

shutter > /dev/null 2>&1 &

