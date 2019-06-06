#!/bin/bash

update-initramfs -u -k all  

grub-install --recheck /dev/sda  

update-grub
