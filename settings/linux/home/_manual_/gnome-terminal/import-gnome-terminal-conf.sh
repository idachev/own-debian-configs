#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

gconftool-2 --load "${DIR}/gnome-terminal-conf.xml"

