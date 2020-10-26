#!/bin/bash

sudo -H apt-get update

sudo -H apt-get -y install python-software-properties debconf-utils apt-transport-https \
 ca-certificates curl software-properties-common dos2unix curl gnupg wget aria2 pigz acpi

################################################################################
# Setup for latest Docker CE

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo -H apt-key add -

sudo -H apt-key fingerprint 0EBFCD88

UBUNTU_RELEASE=bionic

sudo rm /etc/apt/sources.list.d/docker.list
echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu ${UBUNTU_RELEASE} stable" | \
  sudo -H tee /etc/apt/sources.list.d/docker.list

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

sudo -H dpkg --add-architecture i386

sudo -H apt-get update

sudo -H apt-get -y install openjdk-8-jdk openjdk-8-dbg openjdk-8-source
sudo -H apt-get -y install openjdk-11-jdk openjdk-11-dbg openjdk-11-source

sudo -H apt-get -y install htop ncdu vim tmux zsh git gitk zip aspell aptitude \
 keychain gparted smartmontools build-essential nvme-cli python-pip exuberant-ctags \
 cpulimit python3-pip \
 pcsc-tools pcscd opensc libnss3-tools sshpass nmap python-pyqtgraph socat \
 pyqt4-dev-tools lrzip p7zip p7zip-full libimage-exiftool-perl \
 ffmpeg postgresql-client python-dev fdupes fslint gthumb mc archivemount \
 openssh-server maven libcurl4-openssl-dev gcc g++ make pv acpitool

sudo apt-get install azure-cli

# Mongo shell and tools
sudo -H apt-get -y install mongodb-org-shell mongodb-org-tools

# ia32-libs is only available in mint - separate in new line to not fail above in Ubuntu
sudo -H apt-get -y install ia32-libs

sudo -H pip install -U pip 
sudo -H pip install setuptools
sudo -H pip install jump
sudo -H pip install docker-compose
sudo -H pip install pbkdf2
sudo -H pip install bcrypt
sudo -H pip install RBTools
sudo -H pip install natsort
sudo -H pip install numpy

################################################################################
# Setup for nodejs and angular/cli

curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
sudo -H apt-get -y install nodejs

sudo -H npm install -g @angular/cli

################################################################################
# Install docker
#

sudo -H apt-get -y install docker-ce

sudo groupadd docker
sudo gpasswd -a "${USER}" docker
