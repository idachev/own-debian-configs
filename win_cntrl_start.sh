#!/bin/bash
#set -v

WIN_CLASS=$1
PRG=$2

# check if the program has a window visible
FOUND=$(wmctrl -l -x | awk -F ' ' "BEGIN {found=0;} {if (\$3 == \"$WIN_CLASS\") {found=1;}} END {print found;}")
#echo $FOUND

# find on which desctop is the program window
WIN_DESKTOP=$(wmctrl -l -x | awk -F ' ' "BEGIN {found=-2;} {if (\$3 == \"$WIN_CLASS\") {found=\$2;}} END {print found;}")
#echo $WIN_DESKTOP

# find the current desktop number
CUR_DESKTOP=$(wmctrl -d | awk -F ' ' "BEGIN {found=-3;} {if (\$2 == \"*\") {found=\$1;}} END {print found;}")
#echo $CUR_DESKTOP

if [ $FOUND -eq 1 ]; then
	if [ ! $CUR_DESKTOP -eq $WIN_DESKTOP ]; then
		# move to current desktop
		wmctrl -x -r "$WIN_CLASS" -t $CUR_DESKTOP
	fi
	# and activate the window
	wmctrl -x -a "$WIN_CLASS"

	# Set window to sticky to be visible on all virtual desktops
# do not use it just move the window to the desktop
#	wmctrl -x -F -r "$WIN_CLASS" -b toggle,sticky

	# Bring widnow to main desktop
#	wmctrl -x -F -R "$WIN_CLASS"

else
	$PRG &
fi

