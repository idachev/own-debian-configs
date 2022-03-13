#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

${DIR}/apt_install_no_gui_focal.sh

wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | \
  sudo apt-key add -

rm /etc/apt/sources.list.d/google-chrome.list
echo "deb http://dl.google.com/linux/chrome/deb/ stable main" | \
  sudo tee /etc/apt/sources.list.d/google-chrome.list

sudo -H apt-add-repository -y ppa:jtaylor/keepass

sudo -H add-apt-repository -y ppa:linuxuprising/shutter

sudo -H apt update

packages=( shutter gnome-web-photo unrtf antiword poppler-utils \
  dconf-cli dconf-editor dconf-tools google-chrome-beta slack-desktop \
  keepass2 xdotool okular kazam ttf-dejavu-core glogg xbacklight kate \
  handbrake psensor parcellite gwenview kdiff3 x2goclient pgadmin3 \
  libreoffice gpick spotify-client font-manager python-gtk2 xdotool \
  gconf-editor vlc )

for i in "${packages[@]}"; do
    sudo -H apt install -y "$i"
done

pip install opencv-python

"${DIR}/gnome_terminal_profile.sh" import "${DIR}/gnome_terminal_profile_default.conf"

