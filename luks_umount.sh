#!/bin/bash
[ "$1" = -x ] && shift && set -x

if [ "$(id -u)" -ne 0 ]; then
  echo "Requires sudo to start me." >&2
  exit 1
fi

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <partition-device>" >&2
  exit 1
fi

PARTITION_DEV=$1

LUKS_NAME="secure"$(echo "$PARTITION_DEV" | sed -e 's/\//_/g')
LUKS_DEV="/dev/mapper/$LUKS_NAME"

if [ ! -L "$LUKS_DEV" ]; then
  echo -e "Luks dev does not exist: $LUKS_DEV"
  exit 2
fi

set -e

echo -e "\nUnmounting the luks dev: $LUKS_DEV"
umount "$LUKS_DEV"

echo -e "\nSyncing before close..."
sync

if grep -q "^$LUKS_DEV " /proc/mounts; then
  echo -e "Device is still mounted, aborting close: $LUKS_DEV" >&2
  exit 3
fi

echo -e "\nGet luks status before close..."
cryptsetup status "$LUKS_NAME"

echo -e "\nClosing luks dev..."
cryptsetup close "$LUKS_NAME"
