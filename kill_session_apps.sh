#!/bin/bash

apps=( pidgin skype firefox thunderbird glipper )

wclasses=( Navigator.Firefox Mail.Thunderbird skype.Skype Pidgin.Pidgin )

# if you provide display as first argument
# close all desired windows before init kill
if [ -n "$1" ]; then
  export DISPLAY=$1

  echo -e '\nCheck xdotool \n'

  echo -e '\nDump windows...'
  wmctrl -l -x

  echo -e '\nClose windows...'
  for wclass in "${wclasses[@]}"; do
    echo -e "Closing window: $wclass"
    wmctrl -x -c "$wclass"
  done

  echo -e '\nWaiting windows to close...'
  sleep 5
fi

echo 'Check for apps...'
for app in "${apps[@]}"; do
  ps ax | grep "$app"
done

echo -e '\nKill apps...'
for app in "${apps[@]}"; do
  killall "$app"
done

echo -e '\nWaiting apps to exit...'
sleep 5

echo -e '\nCheck for apps again...'
for app in "${apps[@]}"; do
  ps ax | grep "$app"
done
