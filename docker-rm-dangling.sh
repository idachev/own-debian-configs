#!/bin/bash

echo -e "\nStarted at `date`"

ONE_MB=1024
ONE_GB=1048576

# Linux keeps Docker data on the host. Docker Desktop on macOS keeps it in a VM disk under the user Library.
function dockerDataPath() {
  if [ -d /var/lib/docker ]; then
    echo /var/lib/docker
    return
  fi

  local desktop="${HOME}/Library/Containers/com.docker.docker/Data"
  if [ -d "${desktop}" ]; then
    echo "${desktop}"
    return
  fi

  echo /
}

# 1K-blocks. df -kP is the POSIX form: GNU df and macOS df both print Available in column 4.
function getAvailableSize() {
  local path="$1"
  df -kP "${path}" | awk 'NR==2 {print $4}'
}

DATA_PATH=$(dockerDataPath)
SIZE_BEFORE=$(getAvailableSize "${DATA_PATH}")

echo -e "\nCleanup..."

docker system prune --volumes -f

docker volume ls -qf dangling=true | xargs -r docker volume rm

docker images --no-trunc | grep '<none>' | awk '{ print $3 }' | xargs -r docker rmi

SIZE_AFTER=$(getAvailableSize "${DATA_PATH}")

echo -e "\nMeasured path: ${DATA_PATH}"

if [ -z "${SIZE_BEFORE}" ] || [ -z "${SIZE_AFTER}" ]; then
  echo "Available size: unknown"
  exit 1
fi

echo -e "\nAvailable size before:"
echo "$((SIZE_BEFORE / ONE_GB))G"

echo -e "\nAvailable size after:"
echo "$((SIZE_AFTER / ONE_GB))G"

FREED=$((SIZE_AFTER - SIZE_BEFORE))

echo -e "\nFreed:"
echo "$((FREED / ONE_MB))MB / $((FREED / ONE_GB))G"
