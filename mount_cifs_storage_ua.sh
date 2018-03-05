#!/bin/bash

MOUNT_SRC='\\192.168.11.1\ST750LX0_03_90121'
MOUNT_DST=/mnt/ntfs

sudo mount -t cifs $MOUNT_SRC -o username=admin $MOUNT_DST

echo .

ls -al --color $MOUNT_DST

