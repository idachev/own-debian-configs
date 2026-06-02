#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UBUNTU_RELEASE=noble

KEYRINGS_DIR=/etc/apt/keyrings
sudo -H install -m 0755 -d "${KEYRINGS_DIR}"

sudo -H apt update

# NOTE (24.04 changes vs jammy):
#   - ia32-libs removed upstream (dropped)
#   - apt-key removed -> all third-party repos use signed-by= keyrings
#   - python-dev (py2) gone -> python3-dev
#   - PEP 668: system pip is "externally managed" -> apt for libs, pipx for CLIs
#   - MongoDB 5.0 has no noble build -> 8.0; mongo client is now mongosh

packages=( software-properties-common apt-transport-https debconf-utils \
  ca-certificates dos2unix curl gnupg wget aria2 pigz acpi encfs moreutils autossh )

for i in "${packages[@]}"; do
    sudo -H apt install -y "$i"
done

################################################################################
# Setup for Azure cli

curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | \
    sudo tee "${KEYRINGS_DIR}/microsoft.gpg" > /dev/null
sudo chmod 0644 "${KEYRINGS_DIR}/microsoft.gpg"

echo "deb [arch=amd64 signed-by=${KEYRINGS_DIR}/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${UBUNTU_RELEASE} main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list

################################################################################
# Setup for Kubectl

"${DIR}/install_kubectl.sh"

################################################################################
# Setup for GCloud

curl -sL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    gpg --dearmor | \
    sudo tee "${KEYRINGS_DIR}/cloud.google.gpg" > /dev/null
sudo chmod 0644 "${KEYRINGS_DIR}/cloud.google.gpg"

echo "deb [signed-by=${KEYRINGS_DIR}/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

################################################################################
# Setup for MongoDB (8.0 — first series with a noble build)

curl -sL https://www.mongodb.org/static/pgp/server-8.0.asc | \
    gpg --dearmor | \
    sudo tee "${KEYRINGS_DIR}/mongodb-server-8.0.gpg" > /dev/null
sudo chmod 0644 "${KEYRINGS_DIR}/mongodb-server-8.0.gpg"

echo "deb [ arch=amd64,arm64 signed-by=${KEYRINGS_DIR}/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_RELEASE}/mongodb-org/8.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list

################################################################################
# Setup for Java and others

sudo -H apt update

# openjdk-8 is no longer in the default noble repos; standardize on 21.
packages=( openjdk-21-jdk openjdk-21-dbg openjdk-21-source xsensors \
  htop ncdu vim tmux zsh git gitk zip aspell aptitude keychain gparted smartmontools \
  build-essential nvme-cli universal-ctags npm cpulimit python3-pip pipx python3-venv \
  pcsc-tools pcscd opensc \
  libnss3-tools sshpass nmap python3-pyqtgraph socat lrzip p7zip p7zip-full jq apache2-utils \
  libimage-exiftool-perl ffmpeg postgresql-client python3-dev fdupes gthumb mc progress \
  archivemount openssh-server maven libcurl4-openssl-dev gcc g++ make pv acpitool pavucontrol \
  libpcsclite-dev swig docker.io docker-compose-v2 azure-cli mongodb-mongosh mongodb-database-tools \
  google-cloud-cli brightnessctl kitty-terminfo fd-find )

for i in "${packages[@]}"; do
    sudo -H apt install -y "$i"
done

################################################################################
# Python libraries
# PEP 668: 24.04 marks the system Python as externally managed, so plain
# `pip install` is blocked. Prefer distro packages for libraries.

packages=( python3-setuptools python3-bcrypt python3-natsort python3-numpy python3-validators )

for i in "${packages[@]}"; do
    sudo -H apt install -y "$i"
done

################################################################################
# Python CLI applications -> pipx (isolated venvs, on PATH)

pipx ensurepath
# ensurepath only edits shell rc files; make pipx tools usable in THIS run too.
export PATH="${HOME}/.local/bin:${PATH}"

packages=( rbtools yubikey-manager )

for i in "${packages[@]}"; do
    pipx install "$i"
done

# thirdparty
pipx install git+https://github.com/basak/glacier-cli.git

################################################################################
# Setup for nodejs and angular/cli

#curl -sL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
#sudo -H apt -y install nodejs

#sudo -H npm install -g @angular/cli
