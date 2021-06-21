#!/bin/bash

BATTERY_TRESHOLD=25

NOTIFY_TIMEOUT=15

BATTERY_STATUS=$(acpi -b | grep -i 'battery 0')
BATTERY_LEVEL=`echo $BATTERY_STATUS | sed 's/.*, \([0-9]\+\)\%.*/\1/'`

MSG="\n\nLow battery status!\n\n$BATTERY_STATUS"

echo ${BATTERY_STATUS} | grep -qi ' charging'
if [ $? -eq 0 ]; then
  exit
fi

echo ${BATTERY_STATUS} | grep -qi ' full'
if [ $? -eq 0 ]; then
  exit
fi

if [ $BATTERY_LEVEL -eq 0 ]; then
  exit
fi

if [ $BATTERY_LEVEL -le $BATTERY_TRESHOLD ]; then
  zenity --width 300 --warning --title 'Battery Status' --text "<span font-size=\"xx-large\">$MSG</span>" --timeout $NOTIFY_TIMEOUT 
fi

