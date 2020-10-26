#!/bin/bash

PICS=$1
if [ ! -d $1 ]; then
	echo "Should pass a pictures directory, exit!"
	exit 3
fi

#Change this location if you keep your backgrounds elsewhere.
IMGS=`find -L $PICS -size +100k \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.svg' \) -printf '%p '`

#Find out how many pictures we got
N=`echo $IMGS | wc -w`
#echo "All: $N"

#Take a random number between 1 and N
#That take a number between 0 and N-1. We must to add 1.
((N=(RANDOM%N)+1))
#echo "Random: $N"

BGNAME=`echo $IMGS | cut -d ' ' -f $N`
#echo $BGNAME

# check and only change the desktop if file exist
if [ -f $BGNAME ]; then
# start of gconftool command - all on one line!
gconftool-2 -t str --set /desktop/gnome/background/picture_filename "$BGNAME"
# end of gconftool command

gsettings set org.gnome.desktop.background picture-uri file://${BGNAME}

# start of gconftool command - all on one line!
gconftool-2 -t str --set /desktop/gnome/background/picture_options "stretched"
#Possible values are "none", "wallpaper" (eg tiled), "centered", "scaled", "stretched"
# end of gconftool command
fi

