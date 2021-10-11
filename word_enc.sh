#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TMP_FILE=$(mktemp)

echo -n "Read password: "
read -s PASSWORD_1
echo
echo -n "Repeat password: "
read -s PASSWORD_2
echo

if [[ "${PASSWORD_1}" != "${PASSWORD_2}" ]]; then
  echo "Passwords do not match"
  exit 1
fi

echo -n "Number of words: "
read NUMBER_WORDS

echo -n "Encrypt y/n: "
read ENCRYPT

DO_DECRYPT_FLAG="-d"
if [[ "${ENCRYPT}" == "y" ]]; then
  DO_DECRYPT_FLAG=""
fi

OPEN_SSL_ENC="openssl enc -aes-256-cbc -pass env:PASSWORD_1 "${DO_DECRYPT_FLAG}" -a -iter 10000 -md md5 -in "${TMP_FILE}

echo "${OPEN_SSL_ENC}"

for ((i = 1; i <= ${NUMBER_WORDS}; i++)); do
  echo -n "${i}: "
  read -s PLAIN_WORD

  rm -f "${TMP_FILE}"
  touch "${TMP_FILE}"
  echo "${PLAIN_WORD}" >"${TMP_FILE}"

  echo "$(PASSWORD_1="${PASSWORD_1}" ${OPEN_SSL_ENC})"
done
