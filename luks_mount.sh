#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(whoami)" != "root" ]; then
  echo "Requires sudo to start me.";
  exit 1;
fi

PARTITION_DEV=$1
MOUNT_DIR=$2
TARGET_USER=$3

MOUNT_KEY_FILE="/home/${TARGET_USER}/.gnupg/mount/mount$(echo ${PARTITION_DEV} | sed -e 's/\//_/g').enc"

#DISK_DEV=$(echo ${PARTITION_DEV} | sed -e 's/[0-9]$//g')
DISK_DEV=${PARTITION_DEV}

echo -e "\nCheck the SMART info for dev: ${DISK_DEV}"
smartctl -i "${DISK_DEV}"

LUKS_NAME="secure"$(echo ${PARTITION_DEV} | sed -e 's/\//_/g')
LUKS_DEV="/dev/mapper/${LUKS_NAME}"

set -e

echo -e "\nLuks dump for given partition: ${PARTITION_DEV}"
cryptsetup luksDump ${PARTITION_DEV}

if [[ -f "${MOUNT_KEY_FILE}" ]]; then
  echo -e "\n\nUsing ${MOUNT_KEY_FILE} to decrypt:"

  set +e
  MOUNT_PASS=$(cat "${MOUNT_KEY_FILE}" | sudo -u ${TARGET_USER} gpg --pinentry-mode loopback -q --decrypt)
  set -e


  if [ -z "${MOUNT_PASS}" ]; then
    echo -e "\nMount pass decrypt failed using stdin"
  fi

else
  echo -e "\n\nNot found ${MOUNT_KEY_FILE} using stdin"
fi

echo -e "\n\nMounting with luks on dev: ${LUKS_DEV}"
if [ -z "${MOUNT_PASS}" ]; then
  cryptsetup luksOpen ${PARTITION_DEV} ${LUKS_NAME}
else
  echo -n "${MOUNT_PASS}" | cryptsetup luksOpen ${PARTITION_DEV} ${LUKS_NAME} -d -
fi

echo -e "\n\nDump luks status after open..."
cryptsetup status ${LUKS_NAME}

if [ -z "${MOUNT_DIR}" ]; then
  DISK_LABEL=$(e2label ${LUKS_DEV})
  echo -e "\nUsing disk label: ${DISK_LABEL}"

  MOUNT_DIR="/media/${DISK_LABEL}"
  if [ -d "${MOUNT_DIR}" ]; then
    if [ "$(ls -A ${MOUNT_DIR})" ]; then
      echo -e "There is non empty mount directory: ${MOUNT_DIR}"

      # need to sleep a while to be able to do successful luksClose
      # if the mount dir is existing and not empty
      sleep 1

      echo -e "\nDo luks close on dev: ${LUKS_DEV}"
      cryptsetup luksClose ${LUKS_DEV}
      exit 3
    fi
  else
    mkdir ${MOUNT_DIR}
  fi
fi

echo -e "\nMounting to dir: ${MOUNT_DIR}"
mount -t ext4 ${LUKS_DEV} ${MOUNT_DIR} -o rw,noatime,nosuid,nodev,uhelper=udisks

echo -e "\nListing dir..."
ls -hF --color=tty --group-directories-first -al ${MOUNT_DIR}
