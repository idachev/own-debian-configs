#!/bin/bash

check_dir_exists() {
  DIR_CHECK=${1}
  VAR_NAME=${2}
  if [[ ! -d "${DIR_CHECK}" ]]; then
    >&2 echo "Directory not exists: ${VAR_NAME}=${DIR_CHECK}"
    return 1
  fi
}

check_file_exists() {
  FILE_CHECK=${1}
  VAR_NAME=${2}
  if [[ ! -f "${FILE_CHECK}" ]]; then
    >&2 echo "File not exists: ${VAR_NAME}=${FILE_CHECK}"
    return 1
  fi
}

check_not_empty() {
  VALUE_CHECK=${1}
  VAR_NAME=${2}
  if [[ -z "${VALUE_CHECK}" ]]; then
    >&2 echo "Value is empty: ${VAR_NAME}=${VALUE_CHECK}"
    return 1
  fi
}
