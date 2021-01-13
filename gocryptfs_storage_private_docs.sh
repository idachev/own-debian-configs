#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "${DIR}/gocryptfs_lib.sh"

gocryptfs_mount ~/.storage_private_docs.crypt ~/storage_private_docs "$@"
