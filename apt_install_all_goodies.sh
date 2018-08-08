#!/bin/bash

sudo -H add-apt-repository -y ppa:webupd8team/sublime-text-3
sudo -H add-apt-repository -y ppa:ricotz/experimental
sudo -H add-apt-repository -y ppa:webupd8team/java

wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -

sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'

sudo -H dpkg --add-architecture i386

sudo -H apt-get update

sudo -H apt-get -y install htop ncdu vim tmux zsh git gitk zip aspell ttf-dejavu-core \
 glogg aptitude keychain xbacklight gparted sublime-text-installer kate smartmontools \
 handbrake build-essential nvme-cli psensor oracle-java8-installer oracle-java8-set-default \
 google-chrome-beta python-pip exuberant-ctags parcellite slack-desktop gwenview \
 cpulimit kdiff3 shutter libgoo-canvas-perl pgadmin3 pcsc-tools pcscd opensc \
 libnss3-tools libreoffice sshpass nmap python-pyqtgraph socat pyqt4-dev-tools gpick \
 pdftk ia32-libs lrzip p7zip p7zip-full libimage-exiftool-perl ffmpeg postgresql-client \
 python-dev fdupes spotify-client fslint gthumb mc font-manager archivemount openssh-server \
 maven libcurl4-openssl-dev

sudo groupadd docker
sudo gpasswd -a $USER docker

sudo -H pip install -U pip
sudo -H pip install setuptools
sudo -H pip install jump
sudo -H pip install docker-compose
sudo -H pip install pbkdf2
sudo -H pip install bcrypt
sudo -H pip install RBTools
sudo -H pip install natsort

curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
sudo -H apt-get install nodejs

sudo -H npm install -g @angular/cli
