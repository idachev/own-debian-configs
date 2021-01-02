#!/bin/bash

CRYPT_DIR=~/.storage_private_docs.crypt
MOUNT_DIR=~/storage_private_docs

gocryptfs "${CRYPT_DIR}" "${MOUNT_DIR}"; echo "${MOUNT_DIR}"; ls -al --color "${MOUNT_DIR}"
