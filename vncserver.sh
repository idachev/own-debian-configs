#!/bin/sh
#set -v

# TODO implement to do enable of Xdmcp after its section

if [ "$1" = "-stop" ]; then
	echo
	echo 'Disable the XDMP'
	vncserver -kill :1
	sudo sed -i 's/^Enable\=true/Enable\=false/' /etc/kde4/kdm/kdmrc
	sudo sed -i 's/^\(\*[ \t]\+#\)/#\1/' /etc/kde4/kdm/Xaccess
	sudo service kdm restart
    exit
fi

echo
echo 'Enable enable the XDMP'
sudo sed -i 's/^Enable\=false/Enable\=true/' /etc/kde4/kdm/kdmrc
sudo sed -i 's/^#\(\*[ \t]\+#\)/\1/' /etc/kde4/kdm/Xaccess
sudo service kdm restart

# To enable showing KDE login screen use:
# -query localhost
# Also enable XDMP from kde


vncserver :1 -geometry 1280x800 -depth 16 -query localhost -fp /usr/share/fonts/X11/misc,/usr/share/fonts/X11/cyrillic,/usr/share/fonts/X11/Type1,/usr/share/fonts/X11/75dpi,/usr/share/fonts/X11/100dpi -DisconnectClients=0 -NeverShared passwordFile=${HOME}/.vnc/passwd

