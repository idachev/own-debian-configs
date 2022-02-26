#!/bin/bash

# To easy execute this do:
# wget https://github.com/idachev/own-debian-configs/raw/master/_transform_focal.sh; chmod +x ./_transform_focal.sh; . ./_transform_focal.sh; rm ./_transform_focal.sh; cd ~/

TARGET_DIR=~/bin

if ! mkdir "${TARGET_DIR}"; then
  echo -e "\nCreate ${TARGET_DIR} failed"
  exit -1
fi

cd ${TARGET_DIR}

sudo apt update
sudo apt install -y git

git clone https://github.com/idachev/own-debian-configs.git .

find . -type f -not -path "./.git/*" -print0 | xargs -0 sed -i "s/\/home\/idachev/${HOME}/g"

./apt_install_no_gui_focal.sh

cd ${TARGET_DIR}/settings/linux/home
. create_links

cd ${TARGET_DIR}

echo -e "\nTrasnform completed please relogin"
echo -e "\n\nFor desktop mint/ubuntu with GUI check ~/bin/apt_install_all_goodies_focal.sh\n"

