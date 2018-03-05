#!/bin/bash

if [ "$(whoami)" != "root" ]; then
	echo "Requires sudo to start me.";
	exit 1;
fi

DEVICE="wext"
CONFIG=$1
INTERFACE=$2

print_usage()
{
	echo -e "Usage $0"
	echo -e "\t<config file> <interface>\t- to create a connection"
	echo -e "\t-stop <interface>\t\t- to disconnect a connection"
	echo -e ""
	echo -e "The content of config file should be for WPA(2):"
	echo -e "(this is preffered way for high speed in case of 802.11n)"
}

if [ "$CONFIG" = "-stop" ]; then
	if [ -z $INTERFACE ]; then
		echo "Expected after -stop to pass the interface."
		print_usage
		exit 1
	fi
	echo
	echo "Disconnect from access point and stop interface: $INTERFACE"
	dhclient -q -r $INTERFACE > /dev/null 2>&1
	ifconfig $INTERFACE down
	wpa_cli terminate
    exit 0
elif [ ! -f $CONFIG ]; then
	echo "Expected to pass valid config file."
	print_usage
	exit 1
elif [ -z $INTERFACE ]; then
	echo "Expected after config file to pass the interface."
	print_usage
	exit 1
fi

echo
echo "Using config: $1"
echo "Using interface: $2"
echo
echo -e "In order to work this script you should disable/uninstall"
echo -e "the wireless network from GNOME/KDE network manager."
echo
echo -e "To change the access point use this config:\n$CONFIG"
echo
echo -e "To scan for access points use this command:\nsudo ifconfig $INTERFACE up; sudo iwlist $INTERFACE scan"
echo
echo -e "To disconnect from the access point use this command:\n$0 -stop <interface>"

# make temp log file
TMP_LOG="$(mktemp /tmp/wpa_connect_log.XXXXXXXXXX)"

echo
echo "Cleanup old connections if exists..."

# remove the dhcp client IPs for this address
dhclient -q -r $INTERFACE > /dev/null 2>&1

# terminate existing wpa_supplicant
wpa_cli terminate > /dev/null 2>&1

# bring down the interface
ifconfig $INTERFACE down

# some wireless configuration
iwconfig $INTERFACE mode ad-hoc

iwconfig $INTERFACE channel 4

ip addr add 169.254.34.2/16 dev $INTERFACE

# bring up the interface
ifconfig $INTERFACE up

# call wpa_supplicant in daemon mode -B
echo
echo "Starting wpa_supplicant check log file: $TMP_LOG"
wpa_supplicant -B "-D$DEVICE" "-i$INTERFACE" "-c$CONFIG" -dd -t "-f$TMP_LOG"

# this one will try to obtain new IP from DHCP
echo
echo "Adding addresses..."
ip addr add 169.254.34.2/16 dev $INTERFACE

# load custom routes if script exists
BASEDIR=$(dirname $0)
CUSTOM_ROUTES=$BASEDIR/custom_routes.sh
if [ -f $CUSTOM_ROUTES ]; then
	echo
	echo "Running custom routes script: $CUSTOM_ROUTES"
	. $CUSTOM_ROUTES
fi

