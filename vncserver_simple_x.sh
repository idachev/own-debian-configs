#!/bin/bash
#set -v

# TODO implement to do enable of Xdmcp after its section

if [ "$1" = "-stop" ]; then
	echo
	echo 'Disable the XDMP'
	vncserver -kill :1
    exit
fi

# To enable showing KDE login screen use:
# -query localhost
# Also enable XDMP from kde/gdm

#RESOLUTION=1280x800
RESOLUTION=1420x800

vncserver :1 -geometry $RESOLUTION -depth 16 -fp /usr/share/fonts/X11/misc,/usr/share/fonts/X11/cyrillic,/usr/share/fonts/X11/Type1,/usr/share/fonts/X11/75dpi,/usr/share/fonts/X11/100dpi -DisconnectClients=0 -NeverShared passwordFile=/home/idachev/.vnc/passwd
