#!/bin/bash

EXT="$1"
TYP="$2"

if [ -z "${EXT}" ] || [ -z "${TYP}" ]; then
  echo "Expected 2 argument the <media extension like: jpg, mp4, mov, avi...> <type: img or vid>"
  exit 1
fi

EXT=$(echo ${EXT} | tr '[:upper:]' '[:lower:]')
EXT_UPPER=$(echo ${EXT} | tr '[:lower:]' '[:upper:]')

# first do all lower case
echo
echo "Rename files .${EXT_UPPER} to lower case .${EXT}"
rename -v -f 'y/A-Z/a-z/' *."${EXT_UPPER}"
rename -v -f 'y/A-Z/a-z/' *."${EXT}"

echo "Remove spaces from file names replace with: '_'"
rename -v -f 'y/ /_/' *."${EXT}"

# add date taken to the file modify
echo
echo 'Set file modify date.'
exiftool '-DateTimeOriginal>FileModifyDate' *."${EXT}"

# rename with adding date taken in our case
# the modified file system modify date from above
echo
echo 'Rename files by adding date and time as prefix.'
exiftool '-FileName<FileModifyDate' -d %Y%m%d_%H%M%S_%%f.%%e *."${EXT}"

if [ "${TYP}" = "img" ]; then
  rename 's/(^[0-9]{8})_([0-9]{6})_.*\.'"${EXT}"'/img_$1_$2.'"${EXT}"'/g' *."${EXT}"
elif [ "${TYP}" = "vid" ]; then
  rename 's/(^[0-9]{8})_([0-9]{6})_.*\.'"${EXT}"'/vid_$1_$2.'"${EXT}"'/g' *."${EXT}"
else
  echo "Unexpected type: ${TYP}"
fi

