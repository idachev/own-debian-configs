#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  echo "Requires sudo to start me.";
  exit 1;
fi

PARTITION_DEV=$1
MOUNT_DIR=$2
DISK_DEV=$(echo $PARTITION_DEV | sed -e 's/[0-9]$//g')

echo "\nCheck the SMART info for dev: $DISK_DEV"
smartctl -i -T permissive -d sat "$DISK_DEV"

LUKS_NAME="secure"$(echo $PARTITION_DEV | sed -e 's/\//_/g')
LUKS_DEV="/dev/mapper/$LUKS_NAME"

set -e

echo -e "\nLuks dump for given partition: $PARTITION_DEV"
cryptsetup luksDump $PARTITION_DEV

echo -e "\n\nMounting with luks on dev: $LUKS_DEV"
cryptsetup luksOpen $PARTITION_DEV $LUKS_NAME

echo -e "\n\nDump luks status after open..."
cryptsetup status $LUKS_NAME

if [ -z "${MOUNT_DIR}" ]; then
  DISK_LABEL=$(e2label $LUKS_DEV)
  echo -e "\nUsing disk label: $DISK_LABEL"

  MOUNT_DIR="/media/$DISK_LABEL"
  if [ -d "$MOUNT_DIR" ]; then
    if [ "$(ls -A $MOUNT_DIR)" ]; then
      echo -e "There is non empty mount directory: $MOUNT_DIR"

      # need to sleep a while to be able to do successful luksClose
      # if the mount dir is existing and not empty
      sleep 1

      echo -e "\nDo luks close on dev: $LUKS_DEV"
      cryptsetup luksClose $LUKS_DEV
      exit 3
    fi
  else
    mkdir $MOUNT_DIR
  fi
fi

echo -e "\nMounting to dir: $MOUNT_DIR"
mount -t ext4 $LUKS_DEV $MOUNT_DIR -o rw,noatime,nosuid,nodev,uhelper=udisks

echo -e "\nListing dir..."
ls -hF --color=tty --group-directories-first -al $MOUNT_DIR
