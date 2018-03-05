#!/bin/bash

FILE=$1
FILE_DIR=`dirname $FILE`
FILE_NAME=`basename $FILE`
FILE_NAME_NOEXT=`echo ${FILE_NAME%.*}`
FILE_EXT=`echo ${FILE_NAME##*.}`

#echo "FILE_DIR=$FILE_DIR"
#echo "FILE_NAME=$FILE_NAME"
#echo "FILE_NAME_NOEXT=$FILE_NAME_NOEXT"
#echo "FILE_EXT=$FILE_EXT"

# nconvert is from ~/bin and is downloaded from XnView
WORKING_FILE="$FILE_DIR/${FILE_NAME_NOEXT}_b+10.$FILE_EXT"
nconvert -q 100 -keepfiledate -brightness 10 -o "$WORKING_FILE" "$FILE"

# nconvert does not set the correct date under Linux
exiftool '-CreateDate>FileModifyDate' "$WORKING_FILE"

