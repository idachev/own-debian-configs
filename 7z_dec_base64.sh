#/bin/bash

INPUT=$1
TMP=$(mktemp "/tmp/7z_dec_base64.XXXXXXXXXX")

rm $TMP
base64 -d "$INPUT" > $TMP

7z x -bb1 $TMP

rm $TMP

