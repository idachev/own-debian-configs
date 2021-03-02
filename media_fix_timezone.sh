#!/bin/bash

if [ -z $1 ]; then
  echo "Expected 1 argument the media extension like: jpg, mp4, mov, avi..."
  exit 1
fi

EXT="$1"

# in some cases we should fix the time zones
# the tool does not support write of mov files so
# we should modify the file system modify date
echo
echo -n 'Do you want to fix the time zone(y/n): '
read -e UANS
if [ "$UANS" = "y" ]; then
  UDEF="+3"
  echo
  echo -n "Hours to fix($UDEF): "
  read -e UFIX

  if [ -z "$UFIX" ]; then
    UFIX="$UDEF"
  fi

  let "AUFIX=(( 0 + $UFIX ))"
  if [ $AUFIX -ge 0 ]; then
    FIX="+=$AUFIX"
  else
    let "AUFIX=(( 0 - $UFIX ))"
    FIX="-=$AUFIX"
  fi

  echo
  echo "Fix timezone by $UFIX hours."
  exiftool "-FileModifyDate$FIX" *.$EXT
fi
