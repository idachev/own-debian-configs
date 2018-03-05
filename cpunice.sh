#!/bin/bash
#set -x

if [ "$#" -ne 3 ]; then
  echo "Usage:"
  echo "${0} <process name> <nice level> <cpu limit level %>"
  exit 1
fi

PNAME=$1
NICE_LEVEL=$2
CPU_LIMIT=$3

pid=$(pgrep -u ${LOGNAME} -n ${PNAME})

if [ -z "$pid" ]; then
	echo "No PID for $PNAME" >&2
	exit 1
fi

echo "Found PID: ${pid} for ${PNAME}"

echo "Set nice level to ${NICE_LEVEL}"
renice ${NICE_LEVEL} -p ${pid}
if [ "$?" -ne 0 ]; then
  exit 1
fi

echo "Limit CPU to ${CPU_LIMIT}%"
cpulimit -p ${pid} -l ${CPU_LIMIT} -b
if [ "$?" -ne 0 ]; then
  exit 1
fi

