#!/bin/bash
# Unmount ~/storage_private_docs on macOS (umount, not fusermount).
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${DIR}/gocryptfs_storage_private_docs_osx.sh" unmount "$@"
