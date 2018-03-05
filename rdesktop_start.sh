#!/bin/bash

RT_USER=$2
if [ -z "$RT_USER" ]; then
	RT_USER="$USER"
fi

WH=$3
if [ -z "$WH" ]; then
#	WH="1600x1150"
# WH="1590x1120"
# WH="1440x860"
WH="1590x1120"
fi

# There is problem with the windows clipboard itself when do redirect:
# -r clipboard:CLIPBOARD
# -r clipboard:off

# To redirect sound use this:
# -r sound:local

# To remove window decoration use this:
# -D

rdesktop $1 -D -u $RT_USER -g $WH -a 16 -z -r clipboard:off

