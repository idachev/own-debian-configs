#!/bin/bash

WAIT_SECONDS=3

sudo killall cinnamon-screensaver

echo -e "\nWait ${WAIT_SECONDS}s the kill..."
sleep ${WAIT_SECONDS}

echo -e "\nReturn back to GUI with Ctrl + F7 or F8"

echo -e "\nExecute in a GUI terminal:"
echo "cinnamon-screensaver > /dev/null 2>&1 &"

