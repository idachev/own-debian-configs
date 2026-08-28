#!/bin/bash
# Mount ~/.storage_private_docs.crypt on macOS using the login Keychain.
# Optional LaunchAgent mounts the same volume at Aqua login.
#
# Usage:
#   gocryptfs_storage_private_docs_osx.sh
#   gocryptfs_storage_private_docs_osx.sh mount
#   gocryptfs_storage_private_docs_osx.sh unmount
#   gocryptfs_storage_private_docs_osx.sh status
#   gocryptfs_storage_private_docs_osx.sh keychain-set
#   gocryptfs_storage_private_docs_osx.sh agent-install
#   gocryptfs_storage_private_docs_osx.sh agent-uninstall
#
# Cipherdir stays local. Do not mount the Dropbox copy.
# Login Keychain unlocks with the Mac login, so login = private docs.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRYPT_DIR="${HOME}/.storage_private_docs.crypt"
MOUNT_DIR="${HOME}/storage_private_docs"
KC_SERVICE="gocryptfs-storage-private-docs"
AGENT_LABEL="com.idachev.gocryptfs-storage-private-docs"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"
AGENT_LOG="${HOME}/Library/Logs/gocryptfs-storage-private-docs.log"
SECURITY="/usr/bin/security"

usage() {
  cat <<EOF
Usage:
  gocryptfs_storage_private_docs_osx.sh
  gocryptfs_storage_private_docs_osx.sh mount
  gocryptfs_storage_private_docs_osx.sh unmount
  gocryptfs_storage_private_docs_osx.sh status
  gocryptfs_storage_private_docs_osx.sh keychain-set
  gocryptfs_storage_private_docs_osx.sh agent-install
  gocryptfs_storage_private_docs_osx.sh agent-uninstall

mount reads the password from the login Keychain (service ${KC_SERVICE}).
keychain-set stores that password. agent-install loads a LaunchAgent at login.
EOF
}

run_stamp() {
  echo "----- $1 $(date '+%Y-%m-%d %H:%M:%S %z') -----"
}

stamp_run() {
  case "$1" in
    -h|--help|help)
      return 0
      ;;
  esac
  run_stamp "start $1"
  trap 'rc=$?; run_stamp "stop '"$1"' exit ${rc}"' EXIT
}

require_macos() {
  if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS." >&2
    exit 1
  fi
}

kc_account() {
  if [ -n "${USER:-}" ]; then
    echo "${USER}"
    return
  fi
  id -un
}

gocryptfs_bin() {
  if [ -x "${HOME}/go/bin/gocryptfs" ]; then
    echo "${HOME}/go/bin/gocryptfs"
    return 0
  fi
  command -v gocryptfs 2>/dev/null || true
}

uid() {
  if [ "$(id -u)" -ne 0 ]; then
    id -u
    return
  fi
  if [ -n "${SUDO_UID:-}" ]; then
    echo "${SUDO_UID}"
    return
  fi
  stat -f %u /dev/console
}

job_loaded() {
  launchctl print "$1" >/dev/null 2>&1
}

is_mounted() {
  /sbin/mount | command grep -F " on ${MOUNT_DIR} " >/dev/null
}

ensure_never_index() {
  command touch "${MOUNT_DIR}/.metadata_never_index"
}

wait_until_mounted() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if is_mounted; then
      return 0
    fi
    sleep 1
  done
  return 1
}

keychain_has_item() {
  "${SECURITY}" find-generic-password -s "${KC_SERVICE}" -a "$(kc_account)" >/dev/null 2>&1
}

keychain_secret_readable() {
  "${SECURITY}" find-generic-password -w -s "${KC_SERVICE}" -a "$(kc_account)" >/dev/null 2>&1
}

wait_for_keychain() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if keychain_secret_readable; then
      return 0
    fi
    sleep 1
  done
  if keychain_has_item; then
    echo "Keychain item exists but the password is not readable: service ${KC_SERVICE} account $(kc_account)" >&2
  else
    echo "Keychain item not found: service ${KC_SERVICE} account $(kc_account)" >&2
    echo "Do: ${DIR}/gocryptfs_storage_private_docs_osx.sh keychain-set" >&2
  fi
  return 1
}

clear_finder_junk() {
  local leftover
  leftover="$(command ls -A "${MOUNT_DIR}" 2>/dev/null || true)"
  case "${leftover}" in
    ""|.DS_Store)
      command rm -f "${MOUNT_DIR}/.DS_Store"
      ;;
  esac
}

require_cipherdir() {
  if [ ! -f "${CRYPT_DIR}/gocryptfs.conf" ]; then
    echo "Not a gocryptfs cipherdir: ${CRYPT_DIR}" >&2
    exit 1
  fi
}

do_mount() {
  local bin
  require_cipherdir
  if is_mounted; then
    echo "Already mounted: ${MOUNT_DIR}"
    ensure_never_index
    return 0
  fi
  wait_for_keychain
  bin="$(gocryptfs_bin || true)"
  if [ -z "${bin}" ]; then
    echo "gocryptfs not found (expected ${HOME}/go/bin/gocryptfs)" >&2
    exit 1
  fi
  command mkdir -p "${MOUNT_DIR}"
  clear_finder_junk
  "${bin}" \
    -ko noappledouble,noapplexattr \
    -extpass "${SECURITY}" \
    -extpass find-generic-password \
    -extpass=-w \
    -extpass=-s \
    -extpass "${KC_SERVICE}" \
    -extpass=-a \
    -extpass "$(kc_account)" \
    "${CRYPT_DIR}" "${MOUNT_DIR}"
  ensure_never_index
  echo "Mounted ${CRYPT_DIR} on ${MOUNT_DIR}"
  echo "Plaintext path: ${HOME}/personal/docs/private -> ${MOUNT_DIR}/docs"
}

do_unmount() {
  if ! is_mounted; then
    echo "Not mounted: ${MOUNT_DIR}"
    return 0
  fi
  /sbin/umount "${MOUNT_DIR}"
  echo "Unmounted ${MOUNT_DIR}"
}

do_status() {
  local bin loaded plist_state kc_state mount_state
  bin="$(gocryptfs_bin || true)"
  if is_mounted; then
    mount_state="mounted"
  else
    mount_state="not mounted"
  fi
  if keychain_has_item; then
    kc_state="present"
  else
    kc_state="missing"
  fi
  if [ -f "${AGENT_PLIST}" ]; then
    plist_state="present"
  else
    plist_state="missing"
  fi
  if job_loaded "gui/$(uid)/${AGENT_LABEL}"; then
    loaded="loaded"
  else
    loaded="not loaded"
  fi
  echo "cipherdir:  ${CRYPT_DIR}"
  echo "mount:      ${MOUNT_DIR} (${mount_state})"
  echo "gocryptfs:  ${bin:-missing}"
  echo "keychain:   ${KC_SERVICE} / $(kc_account) (${kc_state})"
  echo "agent plist:${AGENT_PLIST} (${plist_state})"
  echo "agent job:  gui/$(uid)/${AGENT_LABEL} (${loaded})"
}

do_keychain_set() {
  local pass pass2
  printf "gocryptfs password: "
  read -r -s pass
  printf "\nAgain: "
  read -r -s pass2
  printf "\n"
  if [ -z "${pass}" ]; then
    echo "Empty password." >&2
    exit 1
  fi
  if [ "${pass}" != "${pass2}" ]; then
    echo "Passwords do not match." >&2
    exit 1
  fi
  "${SECURITY}" add-generic-password \
    -a "$(kc_account)" \
    -s "${KC_SERVICE}" \
    -A \
    -U \
    -w "${pass}"
  echo "Stored Keychain item ${KC_SERVICE} for $(kc_account)"
}

write_agent_plist() {
  local script
  script="${DIR}/gocryptfs_storage_private_docs_osx.sh"
  command mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
  cat > "${AGENT_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AGENT_LABEL}</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${script}</string>
    <string>mount</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${AGENT_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${AGENT_LOG}</string>
</dict>
</plist>
EOF
}

bootout_if_loaded() {
  local target="$1"
  local rc=0
  job_loaded "${target}" || return 0
  launchctl bootout "${target}" || rc=$?
  if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 3 ]; then
    echo "WARNING: bootout ${target} failed (exit ${rc})." >&2
    return "${rc}"
  fi
}

do_agent_install() {
  local id target
  if ! keychain_has_item; then
    echo "Keychain item not found: service ${KC_SERVICE} account $(kc_account)" >&2
    echo "Do: ${DIR}/gocryptfs_storage_private_docs_osx.sh keychain-set" >&2
    exit 1
  fi
  require_cipherdir
  write_agent_plist
  id="$(uid)"
  target="gui/${id}/${AGENT_LABEL}"
  launchctl enable "gui/${id}/${AGENT_LABEL}"
  bootout_if_loaded "${target}"
  launchctl bootstrap "gui/${id}" "${AGENT_PLIST}"
  echo "Installed LaunchAgent ${AGENT_LABEL}"
  echo "Log: ${AGENT_LOG}"
  if wait_until_mounted; then
    echo "Already mounted: ${MOUNT_DIR}"
    ensure_never_index
    return 0
  fi
  echo "LaunchAgent did not mount in time, mounting from this process"
  do_mount
}

do_agent_uninstall() {
  local id target
  id="$(uid)"
  target="gui/${id}/${AGENT_LABEL}"
  if [ -f "${AGENT_PLIST}" ] || job_loaded "${target}"; then
    launchctl disable "gui/${id}/${AGENT_LABEL}"
    bootout_if_loaded "${target}"
  fi
  command rm -f "${AGENT_PLIST}"
  echo "Removed LaunchAgent ${AGENT_LABEL}"
}

require_macos

cmd="${1:-mount}"
if [ "$#" -gt 0 ]; then
  shift
fi
stamp_run "${cmd}"

case "${cmd}" in
  mount)
    do_mount
    ;;
  unmount|umount)
    do_unmount
    ;;
  status)
    do_status
    ;;
  keychain-set)
    do_keychain_set
    ;;
  agent-install)
    do_agent_install
    ;;
  agent-uninstall)
    do_agent_uninstall
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
