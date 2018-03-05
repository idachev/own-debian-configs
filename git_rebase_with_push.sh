#!/bin/bash
#set -v

backup_args="$*"
branch="${1}"
backup="backup-${branch}"
master="${2}"
origin="${3}"
continue="${4}"

SEP='================================================================================\n'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

fail_after_rebase=0

function exit_if_error {
  if [ ${1} -ne 0 ]; then
    echo -e "\n${SEP}${RED}!!!FAILED!!!${NC}\n"
    if [ ${fail_after_rebase} -ne 0 ]; then
      echo -e "\nPlease resolve above conflicts, then continue with\n${0} ${backup_args} --continue\n"
    fi
    exit ${1}
  fi
}

function usage {
  echo -e "Usage: ${0} <branch name> <master name> <optional origin> [--continue]"
}

if [ "${branch}" = "" ]; then
  echo -e "Expecting branch name"
  usage
  exit 1
fi

if [ "${master}" = "" ]; then
  echo -e "Expecting master name"
  usage
  exit 2
fi

if [ "${origin}" = "" ]; then
  origin="origin"
fi

if [ "${origin}" = "--continue" ]; then
  origin="origin"
  continue="--continue"
fi

if [ "${continue}" = "" ]; then

  echo -e "\n${SEP}Checkout ${master}"
  git checkout ${master}
  exit_if_error ${?}

  echo -e "\n${SEP}Git pull ${origin} ${master}"
  git pull ${origin} ${master}
  exit_if_error ${?}

  echo -e "\n${SEP}Checkout ${branch}"
  git checkout ${branch}
  exit_if_error ${?}

  echo -e "\n${SEP}Git push ${origin} ${branch}"
  git push ${origin} ${branch}
  exit_if_error ${?}

  echo -e "\n${SEP}Git branch to ${backup} before rebase"
  git branch ${backup}
  exit_if_error ${?}

  echo -e "\n${SEP}Rebase ${master} into ${branch}"
  fail_after_rebase=1
  git rebase ${master}
  exit_if_error ${?}
  fail_after_rebase=0

fi

echo -e "\n${SEP}Remove old remote ${origin} ${branch}"
git push ${origin} ":${branch}"
exit_if_error ${?}

echo -e "\n${SEP}Create new remote ${origin} ${branch}"
git checkout ${branch}
git branch --unset-upstream
git push --set-upstream ${origin} ${branch}
exit_if_error ${?}

echo -e "\n${SEP}Remove ${backup}"
git branch -D "${backup}"
exit_if_error ${?}

echo -e "\n${SEP}${GREEN}ALL DONE${NC}\n"
