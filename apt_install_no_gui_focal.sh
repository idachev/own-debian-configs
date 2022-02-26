#!/bin/bash

UBUNTU_RELEASE=focal

sudo -H apt update

packages=( software-properties-common apt-transport-https debconf-utils ia32-libs \
  ca-certificates dos2unix curl gnupg wget aria2 pigz acpi encfs moreutils autossh )

for i in "${packages[@]}"; do
    sudo -H apt install -y "$i"
done

################################################################################
# Setup for Azure cli

curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | \
    sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
 
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${UBUNTU_RELEASE} main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list

################################################################################
# Setup for Java and others

sudo -H dpkg --add-architecture i386

sudo -H apt update

packages=( openjdk-8-jdk openjdk-8-dbg openjdk-8-source \
  openjdk-11-jdk openjdk-11-dbg openjdk-11-source \
  htop ncdu vim tmux zsh git gitk zip aspell aptitude keychain gparted smartmontools \
  build-essential nvme-cli exuberant-ctags npm cpulimit python3-pip pcsc-tools pcscd opensc \
  libnss3-tools sshpass nmap python-pyqtgraph socat pyqt4-dev-tools lrzip p7zip p7zip-full \
  libimage-exiftool-perl ffmpeg postgresql-client python-dev fdupes fslint gthumb mc \
  archivemount openssh-server maven libcurl4-openssl-dev gcc g++ make pv acpitool pavucontrol \
  libpcsclite-dev swig docker.io azure-cli mongodb-org-shell mongodb-org-tools )

for i in "${packages[@]}"; do
    sudo -H apt install -y "$i"
done

pip install -U pip

packages=( setuptools jump pbkdf2 bcrypt RBTools natsort numpy )

for i in "${packages[@]}"; do
  pip install "$i"
done

pip3 install -U pip

packages=( setuptools docker-compose validators yubikey-manager )

for i in "${packages[@]}"; do
  pipe install "$i"
done

# thirdparty pip

pip install git+https://github.com/basak/glacier-cli.git

################################################################################
# Setup for nodejs and angular/cli

#curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
#sudo -H apt -y install nodejs

#sudo -H npm install -g @angular/cli
