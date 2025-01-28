#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NIKI_KEY=B293BC58804329FA

read -r -p "Please enter text to encrypt: " text

echo 'Encrypting with key: '
gpg --list-keys "${NIKI_KEY}"

echo "${text}" | gpg --encrypt --armor --recipient "${NIKI_KEY}"
