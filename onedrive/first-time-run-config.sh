#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "${DIR}/.env"

docker run -it --name onedrive \
  -v "${ONE_DRIVE_CONFIG}:/onedrive/conf" \
  -v "${ONE_DRIVE_DATA}:/onedrive/data" \
  -e "ONEDRIVE_UID:${PUID}}" \
  -e "ONEDRIVE_GID:${PGID}" \
  driveone/onedrive:latest

