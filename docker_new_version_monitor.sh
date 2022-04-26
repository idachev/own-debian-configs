#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MONITOR_IMAGE_NAME=$1
MONITOR_IMAGE=$2
MONITOR_SHA_FILE=$3

MONITOR_SHA=$(cat ${MONITOR_SHA_FILE})

docker pull "${MONITOR_IMAGE}"
CURRENT_SHA=$(docker inspect --format='{{index .RepoDigests 0}}' "${MONITOR_IMAGE}")

echo "Found CURRENT_SHA=${CURRENT_SHA}1"

if [[ "${CURRENT_SHA}" != "${MONITOR_SHA}" ]]; then
    FOUND_NEW_TAGS="Found new SHA for ${MONITOR_IMAGE}\nold: ${MONITOR_SHA}\nnew: ${CURRENT_SHA}\n\
\nTo check for new tag execute:\ndocker_image_find_tag.sh -n ${MONITOR_IMAGE_NAME} -i ${MONITOR_IMAGE}\n\
\nExecute this to update with new version, with proper major minor tag:\
\n~/develop/personal/maven-3-openjdk-11-docker-client/build-and-push.sh 8 4"

    zenity --width 300 --warning --title 'New Version' --text "<span font-size=\"xx-large\">${FOUND_NEW_TAGS}</span>"
fi
