#!/bin/bash
# Install a user LaunchAgent that runs Dropbox sync_laptop_osx.sh on the
# Linux cron schedule: minute 5 every 3 hours.
#
# Usage:
#   sync_laptop_osx_agent.sh install
#   sync_laptop_osx_agent.sh uninstall
#   sync_laptop_osx_agent.sh status
#   sync_laptop_osx_agent.sh print-plist
#
# Separate from the gocryptfs mount LaunchAgent. No RunAtLoad, no KeepAlive.
# Empty-source dosync skip covers a race before the volume is mounted.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

AGENT_LABEL="${AGENT_LABEL:-com.idachev.sync-laptop-osx}"
AGENT_PLIST="${AGENT_PLIST:-${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist}"
AGENT_LOG="${AGENT_LOG:-${HOME}/Library/Logs/sync-laptop-osx.log}"
SYNC_SCRIPT_DEFAULT="${HOME}/Dropbox/sync/sync_laptop_osx.sh"
LAUNCHD_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SCHEDULE_HOURS="0 3 6 9 12 15 18 21"
SCHEDULE_MINUTE=5

usage() {
  cat <<EOF
Usage:
  sync_laptop_osx_agent.sh install
  sync_laptop_osx_agent.sh uninstall
  sync_laptop_osx_agent.sh status
  sync_laptop_osx_agent.sh print-plist

install loads a user LaunchAgent (Aqua, no KeepAlive, no RunAtLoad).
status exits 0 only when the agent is installed, loaded, and the plist
matches the Dropbox sync schedule (minute ${SCHEDULE_MINUTE} every 3 hours).
EOF
}

require_macos() {
  if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS." >&2
    exit 1
  fi
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

resolve_sync_script() {
  local src="${SYNC_SCRIPT:-${SYNC_SCRIPT_DEFAULT}}"
  if [ -e "${src}" ]; then
    command realpath "${src}"
    return 0
  fi
  echo "${src}"
}

require_sync_script() {
  local src
  src="$(resolve_sync_script)"
  if [ ! -x "${src}" ]; then
    echo "Sync script missing or not executable: ${src}" >&2
    exit 1
  fi
}

calendar_intervals_xml() {
  local h
  for h in ${SCHEDULE_HOURS}; do
    cat <<EOF
    <dict>
      <key>Hour</key>
      <integer>${h}</integer>
      <key>Minute</key>
      <integer>${SCHEDULE_MINUTE}</integer>
    </dict>
EOF
  done
}

agent_plist_xml() {
  local script
  script="$(resolve_sync_script)"
  cat <<EOF
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
    <string>doit</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${LAUNCHD_PATH}</string>
  </dict>
  <key>StartCalendarInterval</key>
  <array>
$(calendar_intervals_xml)
  </array>
  <key>StandardOutPath</key>
  <string>${AGENT_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${AGENT_LOG}</string>
</dict>
</plist>
EOF
}

write_agent_plist() {
  command mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
  agent_plist_xml > "${AGENT_PLIST}"
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

plist_has_doit() {
  command grep -Fq '<string>doit</string>' "$1"
}

plist_has_homebrew_path() {
  command grep -Fq '/opt/homebrew/bin' "$1"
}

plist_has_keepalive() {
  command grep -Fq 'KeepAlive' "$1"
}

plist_has_runatload() {
  command grep -Fq 'RunAtLoad' "$1"
}

plist_schedule_ok() {
  local p="$1"
  local h hours
  command grep -Fq '<key>StartCalendarInterval</key>' "${p}" || return 1
  for h in ${SCHEDULE_HOURS}; do
    command grep -Fq "<integer>${h}</integer>" "${p}" || return 1
  done
  command grep -Fq "<integer>${SCHEDULE_MINUTE}</integer>" "${p}" || return 1
  hours="$(command grep -c '<key>Hour</key>' "${p}" || true)"
  [ "${hours}" -eq 8 ]
}

do_status() {
  local id target script plist_state loaded schedule_state doit_state
  local path_state keepalive_state runatload_state ok=0
  id="$(uid)"
  target="gui/${id}/${AGENT_LABEL}"
  script="$(resolve_sync_script)"

  if [ -x "${script}" ]; then
    echo "script:    ${script} (present)"
  else
    echo "script:    ${script} (missing)"
    ok=1
  fi

  if [ -f "${AGENT_PLIST}" ]; then
    plist_state="present"
  else
    plist_state="missing"
    ok=1
  fi
  echo "plist:     ${AGENT_PLIST} (${plist_state})"

  if job_loaded "${target}"; then
    loaded="loaded"
  else
    loaded="not loaded"
    ok=1
  fi
  echo "job:       ${target} (${loaded})"

  if [ -f "${AGENT_PLIST}" ] && plist_schedule_ok "${AGENT_PLIST}"; then
    schedule_state="ok"
  else
    schedule_state="wrong"
    ok=1
  fi
  echo "schedule:  minute ${SCHEDULE_MINUTE} every 3 hours (${schedule_state})"

  if [ -f "${AGENT_PLIST}" ] && plist_has_doit "${AGENT_PLIST}"; then
    doit_state="yes"
  else
    doit_state="no"
    ok=1
  fi
  echo "doit:      ${doit_state}"

  if [ -f "${AGENT_PLIST}" ] && plist_has_homebrew_path "${AGENT_PLIST}"; then
    path_state="ok"
  else
    path_state="wrong"
    ok=1
  fi
  echo "PATH:      ${LAUNCHD_PATH} (${path_state})"

  if [ -f "${AGENT_PLIST}" ] && plist_has_keepalive "${AGENT_PLIST}"; then
    keepalive_state="present"
    ok=1
  else
    keepalive_state="absent"
  fi
  echo "keepalive: ${keepalive_state}"

  if [ -f "${AGENT_PLIST}" ] && plist_has_runatload "${AGENT_PLIST}"; then
    runatload_state="present"
    ok=1
  else
    runatload_state="absent"
  fi
  echo "runatload: ${runatload_state}"
  echo "log:       ${AGENT_LOG}"

  return "${ok}"
}

do_install() {
  local id target
  require_sync_script
  write_agent_plist
  id="$(uid)"
  target="gui/${id}/${AGENT_LABEL}"
  launchctl enable "gui/${id}/${AGENT_LABEL}"
  bootout_if_loaded "${target}"
  launchctl bootstrap "gui/${id}" "${AGENT_PLIST}"
  echo "Installed LaunchAgent ${AGENT_LABEL}"
  echo "Log: ${AGENT_LOG}"
  do_status
}

do_uninstall() {
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

cmd="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "${cmd}" in
  install|agent-install)
    do_install
    ;;
  uninstall|agent-uninstall)
    do_uninstall
    ;;
  status)
    do_status
    ;;
  print-plist)
    agent_plist_xml
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
