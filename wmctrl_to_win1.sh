#!/bin/bash

win_id=$(wmctrl -l -G | grep "$1" | awk '{ print $1 }')

echo "Found win id: $win_id"

wmctrl -i -r "$win_id" -e 0,0,0,0,1600,1175

echo "Last err: $?"

