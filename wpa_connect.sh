#!/bin/bash

if [ "$(whoami)" != "root" ]; then
	echo "Requires sudo to start me.";
	exit 1;
fi

DEVICE="wext"
#DEVICE="nl80211"

# used to restore DNS resolving
LOCAL_INTERFACE=eth0

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
	echo -e "\tctrl_interface=/var/run/wpa_supplicant"
	echo -e ""
	echo -e "\tnetwork={"
	echo -e "\t        ssid=\"ESSID_IN_QUOTES\""
	echo -e "\t        psk=\"Password in quotes\""
	echo -e "\t        key_mgmt=WPA-PSK"
	echo -e "\t        proto=RSN"
	echo -e "\t        pairwise=CCMP"
	echo -e "\t}"
	echo -e ""
	echo -e "The content of config file should be for WPA(1):"
	echo -e "\tap_scan=1"
	echo -e "\tctrl_interface=/var/run/wpa_supplicant"
	echo -e ""
	echo -e "\tnetwork={"
	echo -e "\t        ssid=\"ESSID_IN_QUOTES\""
	echo -e "\t        scan_ssid=0"
	echo -e "\t        proto=WPA"
	echo -e "\t        key_mgmt=WPA-PSK"
	echo -e "\t        psk=\"Password in quotes\""
	echo -e "\t        pairwise=TKIP"
	echo -e "\t        group=TKIP"
	echo -e "\t}"
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

	wpa_cli -i $INTERFACE terminate

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
wpa_cli -i $INTERFACE terminate > /dev/null 2>&1

# restart interface
# DEPRECATED in debian kernel 3.x
#service network-interface restart INTERFACE=$INTERFACE

sleep 1
ifconfig $INTERFACE down
ifconfig $INTERFACE up
sleep 1

# if it is first time we should do initial scan
echo
echo "Do initial scan, dump only stderr..."
# iwlist $INTERFACE scan > /dev/null
iwlist $INTERFACE scan

# some wireless configuration
iwconfig $INTERFACE mode Managed

# call wpa_supplicant in daemon mode -B
echo
echo "Starting wpa_supplicant check log file: $TMP_LOG"
wpa_supplicant -B "-D$DEVICE" "-i$INTERFACE" "-c$CONFIG" -dd -t "-f$TMP_LOG"

# give a chance wpa to make negotiation at least 7-10 seconds
sleep 7

# To propperrly handle DNS resolv then install this:
#sudo apt-get install resolvconf
#
# You can edit this file, to set main info:
#/etc/resolvconf/resolv.conf.d/base

echo
echo "Starting DHCP clilent to optain an IP"
echo
dhclient -v $INTERFACE

# give a chance DHCP client to do its job
echo
echo "Sleep 5s before applying custom routes..."
echo
sleep 5

# load custom routes if script exists
BASEDIR=$(dirname $0)
CUSTOM_ROUTES=$BASEDIR/custom_routes.sh
if [ -f $CUSTOM_ROUTES ]; then
	echo
	echo "Running custom routes script: $CUSTOM_ROUTES"
	. $CUSTOM_ROUTES $INTERFACE
fi

