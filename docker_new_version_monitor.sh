#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MONITOR_IMAGE_NAME=$1
MONITOR_IMAGE=$2
MONITOR_SHA=$3

docker pull "${MONITOR_IMAGE}"
CURRENT_SHA=$(docker inspect --format='{{index .RepoDigests 0}}' "${MONITOR_IMAGE}")

echo "Found CURRENT_SHA=${CURRENT_SHA}"

if [[ "${CURRENT_SHA}" != "${MONITOR_SHA}" ]]; then
    FOUND_NEW_TAGS=$("${DIR}/docker_image_find_tag.sh" -l 1000 -n "${MONITOR_IMAGE_NAME}" -i "${MONITOR_IMAGE}")

    zenity --width 300 --warning --title 'New Version' --text "<span font-size=\"xx-large\">${FOUND_NEW_TAGS}</span>"
fi
