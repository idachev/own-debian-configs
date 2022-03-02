#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TMP_SAFE_DIR="$(mktemp -d)"
TMP_DIR="${TMP_SAFE_DIR}-kubectl-tmp"

mkdir -p "${TMP_DIR}"

function cleanup {
  rm -rf "${TMP_SAFE_DIR}-kubectl-tmp"
  echo -e "\nDeleted temp working directory ${TMP_DIR}"
}

trap cleanup EXIT

cd "${TMP_DIR}"
echo -e "\nUsing tmp dir: $(realpath ${TMP_DIR})"

set -e

curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

curl -sLO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"

echo "$(<kubectl.sha256)  kubectl" | sha256sum --check

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo -e "\nInstalled kubectl: "
ls -al /usr/local/bin/kubectl
