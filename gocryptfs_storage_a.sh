#!/bin/bash

CRYPT_DIR=~/.storage_a.crypt
MOUNT_DIR=~/storage_a

gocryptfs "${CRYPT_DIR}" "${MOUNT_DIR}"; echo "${MOUNT_DIR}"; ls -al --color "${MOUNT_DIR}"
