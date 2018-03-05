#!/bin/bash

DIR="$1"

echo -e "Scanning directory: ${DIR}...\n"

TMP_FILE=$(mktemp /tmp/corrupted.XXXXXXXXX)
SAVE_FILE="$(hostname)-corrupted"
find ${DIR} -exec file {} \; | grep "output error" > ${TMP_FILE}
cat ${TMP_FILE} | awk -F  ":" '{print $1}' > ${SAVE_FILE}
rm ${TMP_FILE}

echo -e "\nResults in ${SAVE_FILE}"

