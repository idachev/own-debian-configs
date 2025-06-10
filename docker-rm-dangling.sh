#!/bin/bash

echo -e "\nStarted at `date`"

DOCKER_LIB=/var/lib/docker

ONE_MB=1024
ONE_GB=1048576

function getAvailableSize() {
  local result=$(df /var/lib/docker --output=avail | sed 1d | tr -d '[:space:]')
  echo "${result}"
}

SIZE_BEFORE=$(getAvailableSize)

echo -e "\nCleanup..."

docker system prune --volumes -f

docker volume ls -qf dangling=true | xargs -r docker volume rm

docker images --no-trunc | grep '<none>' | awk '{ print $3 }' | xargs -r docker rmi

echo -e "\nAvailable size before:"
echo `expr ${SIZE_BEFORE} / ${ONE_GB}`G

SIZE_AFTER=$(getAvailableSize)

echo -e "\nAvailable size after:"
echo `expr ${SIZE_AFTER} / ${ONE_GB}`G

FREED=`expr ${SIZE_AFTER} - ${SIZE_BEFORE}`

echo -e "\nFreed:"
echo `expr ${FREED} / ${ONE_MB}`MB / `expr ${FREED} / ${ONE_GB}`G
