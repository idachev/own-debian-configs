#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT=$(realpath "${1}")
TARGET=$(realpath "${2}")

# ROOT should be the parent of the .ecryptfs and .Private folders

sudo mkdir -p "${TARGET}"
cd "${ROOT}"

echo Type your password:
PASS=$(ecryptfs-unwrap-passphrase .ecryptfs/wrapped-passphrase)
PASS=$(echo "${PASS}" | sed -n '2p')
SIG1=$(head -n1 .ecryptfs/Private.sig)
SIG2=$(tail -n1 .ecryptfs/Private.sig)

echo -e "\nResolved Passphrase:"
echo "|${PASS}|"
echo -e "\nSignatures:"
echo "${SIG1}"
echo "${SIG2}"

echo -e "\nShould be empty:"
sudo keyctl clear @u
sudo keyctl list @u

echo -e "\nDo not type anything:"
echo "${PASS}" | sudo ecryptfs-add-passphrase --fnek

echo -e "\nSould have signatures:"
sudo keyctl list @u

ROOT_PRIVATE="$(realpath .Private)"

echo -e "\nMounting ${ROOT_PRIVATE} on ${TARGET}..."
sudo mount -i -t ecryptfs \
  "${ROOT_PRIVATE}" "${TARGET}" \
  -o key=passphrase,ecryptfs_cipher=aes,ecryptfs_key_bytes=16,ecryptfs_passthrough=no,ecryptfs_enable_filename_crypto=yes,ecryptfs_sig="${SIG1}",ecryptfs_fnek_sig="${SIG2}",passwd="${PASS}"

echo "${TARGET}"
ls -al --color "${TARGET}"

unset -v PASS
