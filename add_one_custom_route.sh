#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  echo "Requires sudo to start me.";
  exit 1;
fi

if [ -z "$INTERFACE" ]; then
  INTERFACE=$1
fi

if [ -z "$INTERFACE" ]; then
  echo "You should specify interface name as first argument."
  exit 1
fi

echo "Executing custom routing for interface: $INTERFACE"

VMAIR_GW=192.168.15.253
VMAIR_NET=192.168.14.0
VMAIR_NETMASK=255.255.254.0
VMAIR_DNS1=212.50.10.51
VMAIR_DNS2=212.50.0.15

IPS=$(nslookup ${1} $VMAIR_DNS1 | grep 'Address: ' | cut -f 2 -d ':' | sed -e 's/ //' | tr '\n' ';')

FOUND_IP=0
IFS=";"
for IP in $IPS
do
  if [ -n "$IP" ]; then
    echo "Add route for ${1}($IP)"
    route -v add -host $IP gw $VMAIR_GW dev $INTERFACE
    FOUND_IP=1
  fi
done


if [ $FOUND_IP -eq 0 ]; then
  echo
  echo "Failed to resolve ${1}"
  echo
fi

echo
echo "Dump routing table after modify..."
echo
route -n

