#!/bin/bash
#set -x

if [ "$#" -ne 4 ]; then
  echo "Usage:"
  echo "${0} <process name> <nice level> <cpu limit level %> <ionice level>"
  exit 1
fi

PNAME=$1
NICE_LEVEL=$2
CPU_LIMIT=$3
IO_NICE=$4

if [ -n "${PNAME}" ] && [ "${PNAME}" -eq "${PNAME}" ] 2>/dev/null; then
  pid=${PNAME}
else
  pid=$(pgrep -u ${LOGNAME} -n ${PNAME})
fi

if [ -z "$pid" ]; then
	echo "No PID for $PNAME" >&2
	exit 1
fi

set -e

echo "Found PID: ${pid} for ${PNAME}"

ps "${pid}"

echo "Set nice level to ${NICE_LEVEL}"
renice ${NICE_LEVEL} -p ${pid}

echo "Limit CPU to ${CPU_LIMIT}%"
cpulimit -p ${pid} -l ${CPU_LIMIT} -b

echo "Set ionice level to ${IO_NICE}"
ionice -p ${pid} -c 2 -n ${IO_NICE}

