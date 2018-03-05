#!/bin/bash
#set -v

WIN_CLASS="Pidgin.Pidgin"

while :
do
	wmctrl -x -F -r "$WIN_CLASS" -b toggle,sticky
	sleep 1
done

