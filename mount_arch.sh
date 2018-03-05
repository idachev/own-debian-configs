#!/bin/bash

MOUNT_SRC=${1}
MOUNT_NAME=mnt_$(basename ${MOUNT_SRC})

MOUNT_BASE=~/mnt

MOUNT_POINT=${MOUNT_BASE}/${MOUNT_NAME}

mkdir -p "${MOUNT_POINT}"

sudo umount "${MOUNT_POINT}"

echo -e "\nList mount point is empty ${MOUNT_POINT}"
ls -al "${MOUNT_POINT}"

echo -e "\nMounting..."
archivemount "${MOUNT_SRC}" "${MOUNT_POINT}"

echo -e "\nList after mount"
ls -al "${MOUNT_POINT}"

echo -e "\n${MOUNT_POINT}"

