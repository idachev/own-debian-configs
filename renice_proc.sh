#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 2 ]; then
  echo "Usage:"
  echo "${0} <process name> <nice level>"
  exit 1
fi

PNAME=$1
NICE_LEVEL=$2

ps ax | grep "${PNAME}" | awk '{print $1}' | xargs renice "${NICE_LEVEL}" -p

