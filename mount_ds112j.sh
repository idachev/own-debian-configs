#!/bin/bash

MOUNT_SRC=idachev-ds112j:/volume1/$1
MOUNT_DST=/media/nfs

echo 'Use ~/lib/SynologyAssistant/SynologyAssistant find the DS112J IP and set it in /etc/fstab as idachev-ds112j'

sudo mount $MOUNT_SRC -o user=idachev $MOUNT_DST

echo .

ls -al --color $MOUNT_DST
