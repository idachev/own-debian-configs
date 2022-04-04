#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOIT=$1

if [ "doit" = "${DOIT}" ]; then
  ~/bin/cleanup_develop_before_backup.sh "${DIR}" | xargs -l1 -ITARGET bash -c "TARGET"
else
  ~/bin/cleanup_develop_before_backup.sh "${DIR}"

  echo -e "\nThis is a dry run to do actual cleanup repeat with:\n$0 doit"
fi
