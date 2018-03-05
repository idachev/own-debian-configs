#!/bin/bash

BASEDIR=$(readlink -f $0)
BASEDIR=$(dirname $BASEDIR)

LOG_FILE=$(mktemp "${TMPDIR:-/tmp/}$(basename $0).XXXXXXXXXXXX")

echo "Log in ${LOG_FILE}"

echo -e "\n\nDo photos cleanup for $1" >> ${LOG_FILE}

${BASEDIR}/photos_cleanup.py "$1" ~/Dropbox/mobile/DCIM/ >> ${LOG_FILE}

zenity --warning --title 'Photos Cleanup' --text "$(cat ${LOG_FILE})"
