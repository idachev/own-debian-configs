#!/bin/bash

VMWARE_SERVICES="vmware-USBArbitrator vmware-workstation-server vmware"

ENABLE="${1}"

function list_services() {
  GREP_FILTER="${1}"
  echo -e "\nListing systemctl for services: ${GREP_FILTER}"
  sudo systemctl list-units --type service | grep --color "${GREP_FILTER}"
}

if [[ "${ENABLE}" == "true" ]]; then

  echo -e "\nEnable VMWare services..."

  for i in ${VMWARE_SERVICES}; do
    sudo systemctl enable "${i}"
    sudo service "${i}" start
  done

elif [[ "${ENABLE}" == "false" ]]; then
  echo -e "\nDisable VMWare services..."

  for i in ${VMWARE_SERVICES}; do
    sudo systemctl disable "${i}"
    sudo service "${i}" stop
  done

else

  >&2 echo -e "Expected true/false argument"
  exit 1

fi

list_services "vmware"
