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

echo
echo "Remove the default route from $INTERFACE we want to use the one from eth0"
route -v del default dev $INTERFACE

echo
echo "First set the static host for gateway"
route -v add -host $VMAIR_GW gw $VMAIR_GW dev $INTERFACE

echo
echo "Then add the network to this gateway"
route -v add -net $VMAIR_NET netmask $VMAIR_NETMASK gw $VMAIR_GW dev $INTERFACE

echo
echo "Add route for DNS1($VMAIR_DNS1) DNS2($VMAIR_DNS2)"
route -v add -host $VMAIR_DNS1 gw $VMAIR_GW dev $INTERFACE
route -v add -host $VMAIR_DNS2 gw $VMAIR_GW dev $INTERFACE

function add_route_dns {
  IPS=$(nslookup $1 $2 | grep 'Address: ' | cut -f 2 -d ':' | sed -e 's/ //' | tr '\n' ';')

  FOUND_IP=0
  IFS=";"
  for IP in $IPS
  do
    if [ -n "$IP" ]; then
      if [[ "$IP" == 10.* ]]; then
        echo "Found IP from internal LAN ignoring: $IP";
        return;
      fi
      echo "Add route for $1($IP)"
      route -v add -host $IP gw $VMAIR_GW dev $INTERFACE
      FOUND_IP=1
    fi
  done

  if [ $FOUND_IP -eq 0 ]; then
    echo
    echo "Failed to resolve $1"
    echo
  fi
}

echo
# Removed ols15.com ols17.com idachev-w520
ROUTE_HOSTS=(lz2gl.dyndns.org bstorage-01.unix-it.net team.thinkorswim.com dict.org gator3250.hostgator.com ivandachev.com imap.gmail.com smtp.gmail.com imap.mail.yahoo.com smtp.mail.yahoo.com imap.hushmail.com smtp.hushmail.com pop.hushmail.com ftp.herbby.com ftp.lz2gl.com 108.171.123.251 193.107.36.33)
for i in "${ROUTE_HOSTS[@]}"
do
  add_route_dns ${i}
  add_route_dns ${i} $VMAIR_DNS1
done

echo
echo "Dump routing table after modify..."
echo
route -n

