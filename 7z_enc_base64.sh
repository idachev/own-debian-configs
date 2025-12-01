#!/bin/bash

INPUT=$1
OUTPUT=$1_enc
TMP=$(mktemp "/tmp/7z_enc_base64.XXXXXXXXXX")

rm $TMP
7z_enc.sh $TMP $INPUT

LSTATUS=$?
if [ $LSTATUS -ne 0 ]; then
  exit $LSTATUS
fi

base64 $TMP > $OUTPUT

rm $TMP

echo "Generated: $OUTPUT"

