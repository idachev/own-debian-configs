#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
# Setup for Kubectl

"${DIR}/install_kubectl.sh"

################################################################################
# Setup for GCloud

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

################################################################################
# Setup for Java and others

wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_RELEASE}/mongodb-org/5.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list

sudo add-apt-repository ppa:apandada1/brightness-controller

sudo -H dpkg --add-architecture i386

sudo -H apt update

packages=( openjdk-8-jdk openjdk-8-dbg openjdk-8-source \
  openjdk-11-jdk openjdk-11-dbg openjdk-11-source xsensors brightness-controller \
  htop ncdu vim tmux zsh git gitk zip aspell aptitude keychain gparted smartmontools \
  build-essential nvme-cli exuberant-ctags npm cpulimit python3-pip pcsc-tools pcscd opensc \
  libnss3-tools sshpass nmap python3-pyqtgraph socat lrzip p7zip p7zip-full jq \
  libimage-exiftool-perl ffmpeg postgresql-client python-dev fdupes gthumb mc progress \
  archivemount openssh-server maven libcurl4-openssl-dev gcc g++ make pv acpitool pavucontrol \
  libpcsclite-dev swig docker.io azure-cli mongodb-org-shell mongodb-org-tools google-cloud-sdk )

for i in "${packages[@]}"; do
    sudo -H apt install -y "$i"
done

pip install -U pip

packages=( setuptools pbkdf2 bcrypt RBTools natsort numpy )

for i in "${packages[@]}"; do
  pip install "$i"
done

pip3 install -U pip

packages=( setuptools docker-compose validators yubikey-manager )

for i in "${packages[@]}"; do
  pip3 install "$i"
done

# thirdparty pip

pip install git+https://github.com/basak/glacier-cli.git

################################################################################
# Setup for nodejs and angular/cli

#curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
#sudo -H apt -y install nodejs

#sudo -H npm install -g @angular/cli
