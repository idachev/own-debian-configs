#!/bin/bash

DST_MOUNT=/mnt/img
IMG="${1}"

if [ "${IMG}" = "" ]; then
  echo "Expect 1 argument the image file"
  exit 1
fi

if [ ! -f "${IMG}" ]; then
  echo "Image: ${IMG} does not exist"
  exit 2
fi

sudo losetup -f

sudo losetup -P /dev/loop0 ${IMG}

sudo fdisk -l

sudo mkdir -p "${DST_MOUNT}"

sudo mount -t ext4 /dev/loop0p1 "${DST_MOUNT}"

echo -e "\nList ${DST_MOUNT}"

sudo ls --color -al "${DST_MOUNT}"

echo -e "\nTo unmount do\nsudo umount ${DST_MOUNT}\nsudo losetup -d /dev/loop0"

