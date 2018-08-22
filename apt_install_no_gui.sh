#!/bin/bash

sudo apt-get install -y python-software-properties debconf-utils

sudo -H add-apt-repository -y ppa:ricotz/experimental
sudo -H add-apt-repository -y ppa:webupd8team/java

sudo -H dpkg --add-architecture i386

sudo -H apt-get update

echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | sudo debconf-set-selections

sudo -H apt-get -y install htop ncdu vim tmux zsh git gitk zip aspell aptitude \
 keychain gparted smartmontools build-essential nvme-cli oracle-java8-installer \
 oracle-java8-set-default python-pip exuberant-ctags cpulimit libgoo-canvas-perl \
 pcsc-tools pcscd opensc libnss3-tools sshpass nmap python-pyqtgraph socat \
 pyqt4-dev-tools pdftk lrzip p7zip p7zip-full libimage-exiftool-perl \
 ffmpeg postgresql-client python-dev fdupes fslint gthumb mc archivemount \
 openssh-server maven libcurl4-openssl-dev mongodb-clients gcc g++ make

# ia32-libs is only available in mint - separate in new line to not fail above in Ubuntu
sudo -H apt-get -y install ia32-libs

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
sudo -H apt-get -y install nodejs

sudo -H npm install -g @angular/cli