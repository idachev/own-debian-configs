#!/bin/bash

if [ "$(whoami)" != "root" ]; then
	echo "Requires sudo to start me.";
	exit 1;
fi

DEVICE="wext"
CMD=$1
INTERFACE=$2

print_usage()
{
	echo -e "Usage $0"
	echo -e "\t<ESSID> <interface>\t- to create a connection to given ESSID"
	echo -e "\t-scan <interface>\t\t- to scan on interface"
	echo -e "\t-stop <interface>\t\t- to disconnect a connection"
	echo -e ""
}

if [ "$CMD" = "-stop" ]; then
	if [ -z $INTERFACE ]; then
		echo "Expected after -stop to pass the interface."
		print_usage
		exit 1
	fi
	echo
	echo "Disconnect from access point and stop interface: $INTERFACE"
	dhclient -q -r $INTERFACE > /dev/null 2>&1
	ifconfig $INTERFACE down
  exit 0
elif [ "$CMD" = "-scan" ]; then
	if [ -z $INTERFACE ]; then
		echo "Expected after -scan to pass the interface."
		print_usage
		exit 1
	fi
	echo
	echo "Scan on interface: $INTERFACE"
	ifconfig $INTERFACE up
  iwlist $INTERFACE scan
  exit 0
elif [ -z $CMD ]; then
	echo "Expected to pass ESSID."
	print_usage
	exit 1
elif [ -z $INTERFACE ]; then
	echo "Expected after ESSID file to pass the interface."
	print_usage
	exit 1
fi

echo
echo "Using ESSID: $1"
echo "Using interface: $2"
echo
echo -e "In order to work this script you should disable/uninstall"
echo -e "the wireless network from GNOME/KDE network manager."
echo
echo -e "To scan for access points use this command:\n$0 -scan $INTERFACE"
echo
echo -e "To disconnect from the access point use this command:\n$0 -stop $INTERFACE"

echo
echo "Cleanup old connections if exists..."

# remove the dhcp client IPs for this address
dhclient -q -r $INTERFACE > /dev/null 2>&1

# restart interface
ifconfig $INTERFACE down
ifconfig $INTERFACE up

# if it is first time we should do initial scan
echo
echo "Do initial scan, dump only stderr..."
#iwlist $INTERFACE scan > /dev/null
iwlist $INTERFACE scan

# some wireless configuration
iwconfig $INTERFACE mode Managed

# connect to open ESSID
iwconfig $INTERFACE essid "$CMD"

sleep 5

# this one will try to obtain new IP from DHCP
echo
echo "Starting DHCP clilent to optain an IP..."
dhclient $INTERFACE

# load custom routes if script exists
BASEDIR=$(dirname $0)
CUSTOM_ROUTES=$BASEDIR/custom_routes.sh
if [ -f $CUSTOM_ROUTES ]; then
	echo
	echo "Running custom routes script: $CUSTOM_ROUTES"
	. $CUSTOM_ROUTES
fi

