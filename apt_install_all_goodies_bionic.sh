#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${DIR}/apt_install_no_gui_bionic.sh

wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | \
  sudo apt-key add -

sudo rm /etc/apt/sources.list.d/sublime-text.list
echo "deb https://download.sublimetext.com/ apt/stable/" | \
  sudo tee /etc/apt/sources.list.d/sublime-text.list

wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | \
  sudo apt-key add -

rm /etc/apt/sources.list.d/google-chrome.list
echo "deb http://dl.google.com/linux/chrome/deb/ stable main" | \
  sudo tee /etc/apt/sources.list.d/google-chrome.list

sudo apt-add-repository -y ppa:jtaylor/keepass

# Recoll - search indexing

sudo add-apt-repository ppa:recoll-backports/recoll-1.15-on

sudo apt-get update

sudo -H apt-get -y install unrtf antiword poppler-utils 
sudo -H pip2 install opencv-python

sudo -H apt-get -y install dconf-cli dconf-editor dconf-tools
sudo -H apt-get -y install sublime-text-installer
sudo -H apt-get -y install google-chrome-beta
sudo -H apt-get -y install slack-desktop
sudo -H apt-get -y install keepass2 xdotool
sudo -H apt-get -y install okular
sudo -H apt-get -y install kazam

sudo -H apt-get -y install ttf-dejavu-core glogg xbacklight kate \
 handbrake psensor parcellite gwenview kdiff3 x2goclient \
 shutter pgadmin3 libreoffice gpick spotify-client font-manager \
 python-gtk2 xdotool

"${DIR}/gnome_terminal_profile.sh" import "${DIR}/gnome_terminal_profile_default.conf"

