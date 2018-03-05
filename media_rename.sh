#!/bin/bash

if [ -z $1 ]; then
	echo "Expected one argument the video extension like: mov, avi..."
	exit 1
fi

EXT="$1"
EXT=$(echo $EXT | tr '[:upper:]' '[:lower:]')
EXT_UPPER=$(echo $EXT | tr '[:lower:]' '[:upper:]')

# first do all lower case
echo
echo "Rename files .$EXT_UPPER to lower case .$EXT"
rename -vf 'y/A-Z/a-z/' *.$EXT_UPPER
rename -vf 'y/A-Z/a-z/' *.$EXT

echo "Remove spaces from file names replace with: '_'"
rename -vf 'y/ /_/' *.$EXT

# add date taken to the file modify
echo
echo 'Set file modify date.'
exiftool '-DateTimeOriginal>FileModifyDate' *.$EXT

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

echo
echo 'If something is going wrong use this to return back names:'
echo 'rename -v "s/.*(mvi_[0-9]*)\.mov/$1.mov/" *.mov'

# rename with adding date taken in our case
# the modified file system modify date from above
echo
echo 'Rename files by adding date and time as prefix.'
exiftool '-FileName<FileModifyDate' -d %Y%m%d-%H%M%S-%%f.%%e *.$EXT
