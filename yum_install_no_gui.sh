#!/bin/bash

sudo -H yum update

sudo -H yum -y install python-software-properties debconf-utils apt-transport-https \
 ca-certificates curl software-properties-common dos2unix

sudo -H yum -y install curl apt-transport-https lsb-release gnupg wget aria2

################################################################################
# Setup for latest Docker CE

sudo yum-config-manager --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

sudo yum update

sudo yum install -y docker-ce docker-ce-cli containerd.io 

sudo systemctl enable docker

################################################################################
# Setup for Java and others

sudo -H yum -y install openjdk-8-jdk openjdk-8-dbg openjdk-8-source
sudo -H yum -y install openjdk-11-jdk openjdk-11-dbg openjdk-11-source

sudo -H yum -y install htop ncdu vim tmux zsh git gitk zip aspell aptitude \
 keychain gparted smartmontools build-essential nvme-cli python-pip exuberant-ctags \
 cpulimit libgoo-canvas-perl \
 pcsc-tools pcscd opensc libnss3-tools sshpass nmap python-pyqtgraph socat \
 pyqt4-dev-tools pdftk lrzip p7zip p7zip-full libimage-exiftool-perl \
 ffmpeg postgresql-client python-dev fdupes fslint gthumb mc archivemount \
 openssh-server maven libcurl4-openssl-dev gcc g++ make pv acpitool

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
# Install docker
#
# To install specific version check
# sudo -H apt-cache madison docker-ce

sudo groupadd docker
sudo usermod -aG docker "${USER}"

