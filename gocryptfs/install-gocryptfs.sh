#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo cp "${DIR}/gocryptfs" /usr/bin/
sudo cp "${DIR}/gocryptfs-xray" /usr/bin/
sudo cp "${DIR}/gocryptfs.1" /usr/share/man/man1/
sudo cp "${DIR}/gocryptfs-xray.1" /usr/share/man/man1/
