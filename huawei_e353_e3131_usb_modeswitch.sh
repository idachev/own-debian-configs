#!/bin/bash

lsusb

echo -e "\nDo USB mode switch..."
sudo usb_modeswitch -J -v 12d1 -p 1f01

sleep 5s

sudo usb_modeswitch -J -v 12d1 -p 1f01

sleep 5s

lsusb

ping -w 15 google.com

