#!/bin/bash

sudo add-apt-repository -y ppa:webupd8team/sublime-text-3
sudo add-apt-repository -y ppa:ricotz/experimental
sudo add-apt-repository -y ppa:webupd8team/java

sudo apt-get update

sudo apt-get -y install htop ncdu vim tmux zsh git gitk zip aspell ttf-dejavu-core \
 glogg aptitude keychain xbacklight gparted sublime-text-installer kate smartmontools \
 handbrake build-essential nvme-cli psensor oracle-java8-installer oracle-java8-set-default \
 google-chrome-beta python-pip exuberant-ctags parcellite skype slack-desktop gwenview \
 cpulimit kdiff3 shutter libgoo-canvas-perl pgadmin3 pgadmin4 pcsc-tools pcscd opensc \
 libnss3-tools libreoffice sshpass nmap

sudo -H pip install -U pip
sudo -H pip install setuptools jump docker-compose pbkdf2 bcrypt RBTools

curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
sudo -H apt-get install nodejs

sudo -H npm install -g @angular/cli
