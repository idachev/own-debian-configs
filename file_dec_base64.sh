#!/bin/bash

IN_FILE=${1}
OUT_FILE=${1}.dec

if [[ "${OUT_FILE}" == *.enc.dec ]]; then
  len=${#OUT_FILE}
  OUT_FILE=${OUT_FILE:0:${len}-8}
fi

openssl enc -aes-256-cbc -d -a -in "${IN_FILE}" -out "${OUT_FILE}"

