#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -e

. ${DIR}/bash_lib.sh

CONFIG_PROPS=${1}

. "${CONFIG_PROPS}"

check_dir_exists "${BACKUP_SRC_DIR}" "BACKUP_SRC_DIR"
check_not_empty "${BACKUP_NAME_FILE}" "BACKUP_NAME_FILE"

if [[ -f "${BACKUP_SRC_DIR}/cleanup_before_backup.sh" ]]; then
  echo -e "\nExecute cleanup before backup..."
  "${BACKUP_SRC_DIR}/cleanup_before_backup.sh"
fi

BASE_SRC_DIR=$(dirname ${BACKUP_SRC_DIR})

DIR_YM_NAME=$(date -u '+%Y')/$(date -u '+%Y%m')
TGZ_NAME="${BACKUP_NAME_FILE}-$(date -u '+%Y%m%d-%H%M%S').tgz"

if [[ -d "${BACKUP_DIR_1}" ]]; then
  BACKUP_DIR_1="${BACKUP_DIR_1}/${DIR_YM_NAME}"

  mkdir -p "${BACKUP_DIR_1}"

  TGZ_FILE="${BACKUP_DIR_1}/${TGZ_NAME}"
else
  TGZ_FILE="${BASE_SRC_DIR}/${TGZ_NAME}"
fi

if [[ -d "${BACKUP_DIR_1_ENCRYPTED}" ]]; then
  BACKUP_DIR_1_ENCRYPTED="${BACKUP_DIR_1_ENCRYPTED}/${DIR_YM_NAME}"

  mkdir -p "${BACKUP_DIR_1_ENCRYPTED}"

  TGZ_FILE_ENC_1="${BACKUP_DIR_1_ENCRYPTED}/${TGZ_NAME}.7z"
fi

if [[ -d "${BACKUP_DIR_2_ENCRYPTED}" ]]; then
  BACKUP_DIR_2_ENCRYPTED="${BACKUP_DIR_2_ENCRYPTED}/${DIR_YM_NAME}"

  mkdir -p "${BACKUP_DIR_2_ENCRYPTED}"

  TGZ_FILE_ENC_2="${BACKUP_DIR_2_ENCRYPTED}/${TGZ_NAME}.7z"
fi

echo -e "\nArchive:"
ls -alh "${BACKUP_SRC_DIR}"

if [ "${USE_SUDO}" = "1" ]; then
  sudo "${DIR}/tar_pigz.sh" "${TGZ_FILE}" "${BACKUP_SRC_DIR}" "${BACKUP_SRC_TAR_EXCLUDE}"

  sudo chown "${USER}:${USER}" "${TGZ_FILE}"
else
  "${DIR}/tar_pigz.sh" "${TGZ_FILE}" "${BACKUP_SRC_DIR}" "${BACKUP_SRC_TAR_EXCLUDE}" 
fi

echo -e "\nCreated tgz:"
ls -alh "${TGZ_FILE}"

if [[ -d "${BACKUP_DIR_1_ENCRYPTED}" ]]; then
  7z_enc.sh "${TGZ_FILE_ENC_1}" "${TGZ_FILE}"

  echo -e "\nCreated encrypted:"
  ls -alh "${TGZ_FILE_ENC_1}"
fi

if [[ -d "${BACKUP_DIR_2_ENCRYPTED}" ]]; then

  cp "${TGZ_FILE_ENC_1}" "${TGZ_FILE_ENC_2}"

  echo -e "\nCopy encrypted:"
  ls -alh "${TGZ_FILE_ENC_2}"
fi

if [[ ! -d "${BACKUP_DIR_1}" ]]; then
  echo -e "\nCleanup:"
  ls -alh "${TGZ_FILE}"
  rm "${TGZ_FILE}"
fi
