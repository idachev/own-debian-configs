#!/bin/bash

# To easy execute this do:
# wget https://github.com/idachev/own-debian-configs/raw/master/_transform_.sh; chmod +x ./_transform_.sh; . ./_transform_.sh; rm ./_transform_.sh; cd ~/; bash

TARGET_DIR=~/bin

if ! mkdir "${TARGET_DIR}"; then
  echo -e "\nCreate ${TARGET_DIR} failed"
  exit -1
fi

cd ${TARGET_DIR}

git clone https://github.com/idachev/own-debian-configs.git .

cd ${TARGET_DIR}/settings/linux/home
. create_links
