#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  echo "Requires sudo to start me.";
  exit 1;
fi

PARTITION_DEV=$1

LUKS_NAME="secure"$(echo $PARTITION_DEV | sed -e 's/\//_/g')
LUKS_DEV="/dev/mapper/$LUKS_NAME"

if [ ! -L "$LUKS_DEV" ]; then
  echo -e "Luks dev does not exist: $LUKS_DEV"
  exit 2
fi

echo -e "Unmounting the luks dev: $LUKS_DEV"
umount $LUKS_DEV

LAST_ERR=$?
if [[ $LAST_ERR -ne 0 ]]; then
  echo "Error on umount: $LAST_ERR, continue..."
fi

echo -e "\nGet luks status before close..."
cryptsetup status $LUKS_NAME

echo -e "\nClosing luks dev..."
cryptsetup luksClose $LUKS_NAME

LAST_ERR=$?
if [[ $LAST_ERR -ne 0 ]]; then
  echo "Error on luks close: $LAST_ERR"
  exit $LAST_ERR
fi

