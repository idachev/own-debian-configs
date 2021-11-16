#!/bin/bash

sudo -H yum update

sudo -H yum -y install debconf-utils ca-certificates dos2unix
sudo -H yum -y install curl gnupg wget aria2 pigz acpi encfs

################################################################################
# Setup for latest Docker CE

sudo yum-config-manager --add-repo \
  https://download.docker.com/linux/centos/docker-ce.repo

sudo yum update

sudo yum install -y docker-ce docker-ce-cli containerd.io

sudo systemctl enable docker

sudo groupadd docker
sudo usermod -aG docker "${USER}"

################################################################################
# Setup for Java and others

sudo -H yum -y install java-1.8.0-openjdk java-1.8.0-openjdk-src \
  java-1.8.0-openjdk-javadoc java-1.8.0-openjdk-demo java-1.8.0-openjdk-devel
sudo -H yum -y install java-11-openjdk java-11-openjdk-src \
  java-11-openjdk-javadoc java-11-openjdk-demo java-11-openjdk-devel 

################################################################################
# Setup Others

sudo -H yum -y install htop ncdu vim tmux zsh git gitk zip aspell
sudo -H yum -y install keychain gparted smartmontools nvme-cli python-pip python3-pip ctags
sudo -H yum -y install cpulimit pcsc-tools opensc sshpass nmap socat lrzip p7zip
sudo -H yum -y install fdupes fslint gthumb mc openssh-server maven gcc make pv sssd-tools

sudo yum -y install epel-release
sudo yum -y localinstall --nogpgcheck \
  https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm

sudo yum -y install ffmpeg ffmpeg-devel

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

sudo -H pip3 install yubikey-manager

sudo sss_override user-add "${USER}" --shell=/bin/zsh
