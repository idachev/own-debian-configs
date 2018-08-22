#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${DIR}/apt_install_no_gui.sh

sudo -H apt-get -y install ttf-dejavu-core glogg xbacklight sublime-text-installer kate \
 handbrake psensor google-chrome-beta parcellite slack-desktop gwenview kdiff3 \
 shutter pgadmin3 libreoffice gpick spotify-client font-manager
