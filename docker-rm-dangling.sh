#!/bin/bash

DOCKER_LIB=/var/lib/docker

SIZE_BEFORE=$(sudo du -hs "${DOCKER_LIB}")

echo -e "\nCleanup..."

docker volume ls -qf dangling=true | xargs -r docker volume rm

docker images --no-trunc | grep '<none>' | awk '{ print $3 }' | xargs -r docker rmi

echo -e "\nDir size before:"
echo "${SIZE_BEFORE}"

echo -e "\nDir size after:"
sudo du -hs "${DOCKER_LIB}"


