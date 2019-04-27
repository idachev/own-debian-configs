#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

gconftool-2 --dump '/apps/gnome-terminal' > "${DIR}/gnome-terminal-conf.xml"

