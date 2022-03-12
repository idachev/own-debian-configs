#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

set -e

echo -e "\nUnmounting the luks dev: $LUKS_DEV"
umount $LUKS_DEV

echo -e "\nGet luks status before close..."
cryptsetup status $LUKS_NAME

echo -e "\nClosing luks dev..."
cryptsetup luksClose $LUKS_NAME
