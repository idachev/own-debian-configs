#!/bin/bash

TARGET_DIR=~/bin

if ! mkdir "${TARGET_DIR}"; then
  echo -e "\nCreate ${TARGET_DIR} failed"
  exit -1
fi

cd ${TARGET_DIR}

git clone https://github.com/idachev/own-debian-configs.git .

cd ${TARGET_DIR}/settings/linux/home
. create_links

