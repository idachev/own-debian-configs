#!/bin/bash
#set -v

branch="${1}"
tag="merged-${branch}"
backup="backup-${branch}"
master="${2}"
backup_master="backup-${master}"
origin="${3}"
backup_master_done=0

SEP='================================================================================\n'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function exit_if_error {
  if [ ${1} -ne 0 ]; then
    echo -e "\n${SEP}${RED}!!!FAILED!!!${NC}\n"
    if [ ${backup_master_done} -ne 0 ]; then
      echo -e "\nCleanup backups...\n"
      git checkout ${master}
      git branch -d "${backup_master}"
      git checkout "${branch}"
      git branch -d "${backup}"

      echo -e "\n${SEP}${RED}!!!WARNING!!!${NC}\nYour branch '${branch}' is NOT on top of '${master}'."
      echo -e "Please rebase and fix conflicts then retry!\n${RED}!!!WARNING!!!${NC}"
    fi
    exit ${1}
  fi
}

function usage {
  echo -e "Usage: ${0} <branch name> <master name> <optional origin>"
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

echo -e "\n${SEP}Checkout ${branch}"
git checkout ${branch}
exit_if_error ${?}

echo -e "\n${SEP}Git push ${origin} ${branch}"
git push ${origin} ${branch}
exit_if_error ${?}

echo -e "\n${SEP}Git branch to ${backup} before merge"
git branch ${backup}
exit_if_error ${?}

echo -e "\n${SEP}Checkout ${master}"
git checkout ${master}
exit_if_error ${?}

echo -e "\n${SEP}Git pull ${origin} ${master}"
git pull ${origin} ${master}
exit_if_error ${?}

echo -e "\n${SEP}Git branch to ${backup_master} before merge"
git branch ${backup_master}
exit_if_error ${?}
backup_master_done=1

echo -e "\n${SEP}Merge fast forward only ${branch} into ${master}"
git merge --ff-only ${branch}
exit_if_error ${?}

echo -e "\n${SEP}Tag ${branch} as ${tag}"
git tag "${tag}" "${branch}"
exit_if_error ${?}

echo -e "\n${SEP}Push tag ${origin} ${tag}"
git push ${origin} ${tag}
exit_if_error ${?}

echo -e "\n${SEP}Push changes ${origin}"
git push ${origin}
exit_if_error ${?}

echo -e "\n${SEP}Remove remote ${origin} ${branch}"
git push ${origin} ":${branch}"
exit_if_error ${?}

echo -e "\n${SEP}Remove local ${branch}"
git branch -d "${branch}"
exit_if_error ${?}

echo -e "\n${SEP}Remove ${backup}"
git branch -d "${backup}"
exit_if_error ${?}

echo -e "\n${SEP}Remove ${backup_master}"
git branch -d "${backup_master}"
exit_if_error ${?}

echo -e "\n${SEP}${GREEN}ALL DONE${NC}\n"
