#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

START_COMMIT=$1
END_COMMIT=$2
JIRA_PROJECT_KEY=$3

git rev-list "${START_COMMIT}..${END_COMMIT}" | \
  xargs -Ii git log --format=%B -n 1 i | \
  sed -En 's/^.*('${JIRA_PROJECT_KEY}'-[0-9]*)[^0-9]*$/\1/p' | \
  sort -u
