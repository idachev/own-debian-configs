#!/bin/bash

IN_FILE=${1}
OUT_FILE=${1}.enc

openssl enc -aes-256-cbc -salt -in "${IN_FILE}" -out "${OUT_FILE}"

