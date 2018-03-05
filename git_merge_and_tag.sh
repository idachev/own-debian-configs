#!/bin/bash
#set -v

branch="${1}"
tag="merged-${1}"
master="${2}"
origin="${3}"

function exit_if_error {
  if [ ${1} -ne 0 ]; then
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

echo -e "\nCheckout ${branch}"
git checkout ${branch}
exit_if_error ${?}

echo -e "\nGit push"
git push ${origin} ${branch}
exit_if_error ${?}

echo -e "\nCheckout ${master}"
git checkout ${master}
exit_if_error ${?}

echo -e "\nGit pull"
git pull ${origin} ${master}
exit_if_error ${?}

echo -e "\nMerge ${branch} into ${master}"
git merge --no-ff -m "Merge branch '${branch}'" ${branch}
exit_if_error ${?}

echo -e "\nTag ${branch} as ${tag}"
git tag "${tag}" "${branch}"
exit_if_error ${?}

echo -e "\nPush tag"
git push ${origin} ${tag}
exit_if_error ${?}

echo -e "\nRemove remote branch"
git push ${origin} ":${branch}"
exit_if_error ${?}

echo -e "\nRemove local branch"
git branch -d "${branch}"
exit_if_error ${?}

echo -e "\nPush changes"
git push ${origin}
exit_if_error ${?}

