#!/bin/bash

gocryptfs_mount() {
  local CRYPT_DIR=$(realpath $1)
  local MOUNT_DIR=$(realpath $2)

  echo -e "\nFirst do -fsck"

  set -e
  gocryptfs -fsck "${CRYPT_DIR}"

  echo -e "\nIf all OK do mount"

  gocryptfs "${CRYPT_DIR}" "${MOUNT_DIR}"
  
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
