#!/bin/bash

UBUNTU_RELEASE=xenial

sudo -H apt-get update

sudo -H apt-get -y install lsb-release
sudo -H apt-get -y install python-software-properties software-properties-common apt-transport-https
sudo -H apt-get -y install debconf-utils ca-certificates dos2unix
sudo -H apt-get -y install curl gnupg wget aria2 pigz acpi encfs

################################################################################
# Setup for latest Docker CE

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo -H apt-key add -

sudo -H apt-key fingerprint 0EBFCD88

sudo rm /etc/apt/sources.list.d/docker.list
echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu ${UBUNTU_RELEASE} stable" | \
  sudo -H tee /etc/apt/sources.list.d/docker.list

sudo -H apt-get -y install docker-ce

sudo groupadd docker
sudo gpasswd -a "${USER}" docker

################################################################################
# Setup for latest Mongo 4.0

# sudo -H apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
# --recv 9DA31620334BD75D9DCB49F368818C72E52529D4

#sudo rm /etc/apt/sources.list.d/mongodb-org-4.0.list
#echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_RELEASE}/mongodb-org/4.0 multiverse" \
# | sudo -H tee /etc/apt/sources.list.d/mongodb-org-4.0.list

################################################################################
# Setup for latest Mongo 3.6

sudo -H apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
 --recv 2930ADAE8CAF5059EE73BB4B58712A2291FA4AD5

sudo rm /etc/apt/sources.list.d/mongodb-org-3.6.list
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_RELEASE}/mongodb-org/3.6 multiverse" \
 | sudo tee /etc/apt/sources.list.d/mongodb-org-3.6.list

################################################################################
# Setup for Azure cli

curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | \
    sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
 
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${UBUNTU_RELEASE} main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list

sudo -H add-apt-repository -y ppa:ubuntuhandbook1/shutter
sudo -H apt update
sudo -H apt install -y libgtk2-appindicator-perl shutter

################################################################################
# Setup for Java and others

sudo -H add-apt-repository -y ppa:ricotz/experimental
sudo -H add-apt-repository -y ppa:webupd8team/java

sudo -H dpkg --add-architecture i386

sudo -H apt-get update

sudo -H apt-get -y install openjdk-8-jdk openjdk-8-dbg openjdk-8-source
sudo -H apt-get -y install openjdk-11-jdk openjdk-11-dbg openjdk-11-source

sudo -H apt-get -y install htop ncdu vim tmux zsh git gitk zip aspell aptitude
sudo -H apt-get -y install keychain gparted smartmontools build-essential nvme-cli exuberant-ctags
sudo -H apt-get -y install cpulimit libgoo-canvas-perl python3-pip python-pip
sudo -H apt-get -y install pcsc-tools pcscd opensc libnss3-tools sshpass nmap python-pyqtgraph socat
sudo -H apt-get -y install pyqt4-dev-tools pdftk lrzip p7zip p7zip-full libimage-exiftool-perl
sudo -H apt-get -y install ffmpeg postgresql-client python-dev fdupes fslint gthumb mc archivemount
sudo -H apt-get -y install openssh-server maven libcurl4-openssl-dev gcc g++ make pv acpitool pavucontrol

sudo apt-get install azure-cli

# Mongo shell and tools
sudo -H apt-get -y install mongodb-org-shell mongodb-org-tools

# ia32-libs is only available in mint - separate in new line to not fail above in Ubuntu
sudo -H apt-get -y install ia32-libs

sudo -H pip install -U pip

sudo -H pip install setuptools
sudo -H pip install jump
sudo -H pip install pbkdf2
sudo -H pip install bcrypt
sudo -H pip install RBTools
sudo -H pip install natsort
sudo -H pip install numpy

sudo -H pip3 install -U pip

sudo -H pip3 install setuptools
sudo -H pip3 install docker-compose

################################################################################
# Setup for nodejs and angular/cli

curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
sudo -H apt-get -y install nodejs

sudo -H npm install -g @angular/cli
