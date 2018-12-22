#!/bin/sh
#set -v

# Use this in case you want to check who is connecting to your desctop
# -accept "popup" -gone "popup"


if [ "$(whoami)" != "root" ]; then
	echo "Requires sudo to start me.";
	exit 1;
fi

if [ -z "$1" ]; then
	echo "Requires to pass auth value.";
	ps ax | grep auth;
	exit 2;
fi

# access raw display
echo auth: $1
x11vnc -rfbauth ${HOME}/.vnc/passwd -bg -rfbport 5900 -forever -noxdamage -solid darkblue -auth $1 -display :0 &

