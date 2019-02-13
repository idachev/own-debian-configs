#!/bin/bash

CONNECTION_PROFILE="Auto Ethernet"

nmcli dev

CURRENT_CONNECTION=$(nmcli device show enp0s31f6 | grep GENERAL.CONNECTION: | awk '{print $2" "$3}')

if [[ "${CURRENT_CONNECTION}" = "${CONNECTION_PROFILE}" ]]; then
  echo -e "\nAlready connected to ${CONNECTION_PROFILE}"
  exit
fi

echo -e "\nConnecting to ${CONNECTION_PROFILE}"

nmcli -p con up "${CONNECTION_PROFILE}" ifname enp0s31f6

sleep 5

nmcli dev

sleep 5

ping -w 15 google.com

