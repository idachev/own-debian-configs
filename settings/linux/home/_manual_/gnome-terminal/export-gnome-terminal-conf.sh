#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

dconf dump /org/gnome/terminal/legacy/profiles:/ > "${DIR}/gnome-terminal-profiles.dconf"

