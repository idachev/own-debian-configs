#!/bin/bash

# ==================================================
# This is used to be able to work from crontab

# Get the pid of dbus session app
DBUS_APP_GREP="xfwm4"

dbus_pid=$(pgrep -u $LOGNAME -n $DBUS_APP_GREP)

if [ -z "$dbus_pid" ]; then
	echo "No DBUS app $DBUS_APP_GREP, exit!" >&2
  return
fi

# Grab the DBUS_SESSION_BUS_ADDRESS variable from app's environment
eval $(tr '\0' '\n' < /proc/$dbus_pid/environ | grep '^DBUS_SESSION_BUS_ADDRESS=')

if [ "$?" != "0" ]; then
  dbus_pid=$(pgrep -u $LOGNAME -n "session")

  if [ -z "$dbus_pid" ]; then
    echo "No DBUS app session, exit!" >&2
    return
  fi

  eval $(tr '\0' '\n' < /proc/$dbus_pid/environ | grep '^DBUS_SESSION_BUS_ADDRESS=')
fi

# Check that we actually found it
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
	echo "Failed to find bus address, exit!" >&2
  return
fi

# export it so that child processes will inherit it
export DBUS_SESSION_BUS_ADDRESS
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"

