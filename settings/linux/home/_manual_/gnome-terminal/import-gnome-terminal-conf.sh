#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

dconf load /org/gnome/terminal/legacy/profiles:/ < "${DIR}/gnome-terminal-profiles.dconf"

