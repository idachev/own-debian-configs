#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat ~/.gnupg/mount/mount_test.enc | gpg --pinentry-mode loopback -q --decrypt
