#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${DIR}"
GIT_SSH_COMMAND='ssh -i ~/.ssh/id_bs_a' git push
