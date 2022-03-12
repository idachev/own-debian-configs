#!/bin/bash

gocryptfs_mount() {
  local CRYPT_DIR=$(realpath $1)
  local MOUNT_DIR=$(realpath $2)
  local DO_FSCK=$3

  echo -e "\nFirst do -fsck"

  set -e

  if [ -n "${DO_FSCK}" ]; then
    gocryptfs -fsck "${CRYPT_DIR}"

    echo -e "\nIf all OK do mount"
  fi

  MOUNT_KEY_FILE="/root/.gnupg/mount/mount"$(echo "${CRYPT_DIR}" | sed -e 's/[\/\.]\+/_/g').enc
  if sudo test -f "${MOUNT_KEY_FILE}"; then
    echo -e "\n\nUsing ${MOUNT_KEY_FILE} to decrypt:"

    MOUNT_PASS=$(sudo cat "${MOUNT_KEY_FILE}" | sudo gpg --pinentry-mode loopback -q --decrypt)
  else
    echo -e "\n\nNot found ${MOUNT_KEY_FILE} using stdin"
  fi

  if [ -z "${MOUNT_PASS}" ]; then
    gocryptfs "${CRYPT_DIR}" "${MOUNT_DIR}"
  else
    echo ${MOUNT_PASS} | gocryptfs "${CRYPT_DIR}" "${MOUNT_DIR}"
  fi

  echo -e "\nListing ${MOUNT_DIR}"
  ls -al --color "${MOUNT_DIR}"

  echo -e "\nTo unmount do"
  echo -e "fusermount -u ${MOUNT_DIR}"
}

gocryptfs_init() {
  local CRYPT_DIR=$(realpath $1)

  echo -e "\nInit new gocryptfs in ${CRYPT_DIR}"

  gocryptfs -init -raw64 "${CRYPT_DIR}"
}
