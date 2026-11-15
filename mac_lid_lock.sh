#!/bin/bash
# Install a user LaunchAgent that locks the screen when the lid closes.
#
# Usage:
#   mac_lid_lock.sh install
#   mac_lid_lock.sh uninstall
#   mac_lid_lock.sh restart
#   mac_lid_lock.sh status
#   mac_lid_lock.sh pause
#   mac_lid_lock.sh resume
#   mac_lid_lock.sh print-plist
#
# With `pmset -a disablesleep 1` a lid close does not sleep the Mac, so
# macOS does not lock it. The agent runs mac_lid_lock (built here from
# mac_lid_lock.c), which runs `pmset displaysleepnow` on a lid close. That
# locks only when System Settings > Lock Screen asks for the password
# immediately after the display turns off; status checks it.
#
# pause stops the lock on lid close until resume, also after a reboot. Use it
# when you work with the lid closed on an external display: displaysleepnow
# turns off every display, the external one too.
#
# The program keeps the last 180 days in the log: at start and on every lid
# change it cuts the older lines.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_LABEL="${AGENT_LABEL:-com.idachev.mac-lid-lock}"
AGENT_PLIST="${AGENT_PLIST:-${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist}"
AGENT_LOG="${AGENT_LOG:-${HOME}/Library/Logs/mac-lid-lock.log}"
PAUSED_FILE="${HOME}/Library/Application Support/mac-lid-lock/paused"
SRC="${DIR}/mac_lid_lock.c"
BIN="${DIR}/mac_lid_lock"

usage() {
  cat <<EOF
Usage:
  mac_lid_lock.sh install
  mac_lid_lock.sh uninstall
  mac_lid_lock.sh restart
  mac_lid_lock.sh status
  mac_lid_lock.sh pause
  mac_lid_lock.sh resume
  mac_lid_lock.sh print-plist

install builds ${BIN} from ${SRC} and loads a user LaunchAgent
(Aqua, RunAtLoad, KeepAlive) that runs it.
status exits 0 only when the agent is loaded and the lock delay is immediate.
pause stops the lock on lid close until resume (for a closed lid on an
external display). It stays paused after a reboot.
EOF
}

require_macos() {
  if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS." >&2
    exit 1
  fi
}

require_user() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "Run it as your user, not root: it installs a user LaunchAgent." >&2
    exit 1
  fi
}

job_loaded() {
  launchctl print "$1" >/dev/null 2>&1
}

build() {
  clang -Os -Wall -Wextra -framework IOKit -framework CoreFoundation \
    -o "${BIN}.tmp" "${SRC}"
  command mv "${BIN}.tmp" "${BIN}"
}

agent_plist_xml() {
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
    <string>${BIN}</string>
    <string>${AGENT_LOG}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>ProcessType</key>
  <string>Background</string>
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
  # bootout returns before the job is gone; bootstrap then fails with exit 5.
  local _
  for _ in $(seq 1 20); do
    job_loaded "${target}" || return 0
    sleep 0.5
  done
  echo "WARNING: ${target} still loaded after bootout." >&2
}

do_status() {
  local target delay ok=0
  target="gui/$(id -u)/${AGENT_LABEL}"

  if [ -x "${BIN}" ]; then
    echo "binary:    ${BIN} (present)"
  else
    echo "binary:    ${BIN} (missing)"
    ok=1
  fi

  if [ -f "${AGENT_PLIST}" ]; then
    echo "plist:     ${AGENT_PLIST} (present)"
  else
    echo "plist:     ${AGENT_PLIST} (missing)"
    ok=1
  fi

  if launchctl print "${target}" 2>/dev/null | grep -q 'state = running'; then
    echo "job:       ${target} (running)"
  else
    echo "job:       ${target} (not running)"
    ok=1
  fi

  delay="$(sysadminctl -screenLock status 2>&1 | sed -n 's/.*screenLock delay is //p')"
  if [ "${delay}" = immediate ]; then
    echo "lock:      password required immediately"
  else
    echo "lock:      delay is '${delay:-unknown}', so a lid close does not lock at once"
    echo "           fix: System Settings > Lock Screen > Require password > Immediately"
    ok=1
  fi
  if [ -e "${PAUSED_FILE}" ]; then
    echo "pause:     paused, a lid close does not lock (mac_lid_lock.sh resume)"
  else
    echo "pause:     not paused"
  fi
  echo "log:       ${AGENT_LOG}"

  return "${ok}"
}

do_install() {
  local id target
  require_user
  build
  command mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
  agent_plist_xml > "${AGENT_PLIST}"
  id="$(id -u)"
  target="gui/${id}/${AGENT_LABEL}"
  launchctl enable "${target}"
  bootout_if_loaded "${target}"
  launchctl bootstrap "gui/${id}" "${AGENT_PLIST}"
  echo "Installed LaunchAgent ${AGENT_LABEL}"
  sleep 1
  do_status
}

do_uninstall() {
  local target
  require_user
  target="gui/$(id -u)/${AGENT_LABEL}"
  if [ -f "${AGENT_PLIST}" ] || job_loaded "${target}"; then
    launchctl disable "${target}"
    bootout_if_loaded "${target}"
  fi
  command rm -f "${AGENT_PLIST}"
  echo "Removed LaunchAgent ${AGENT_LABEL}"
}

do_restart() {
  require_user
  launchctl kickstart -k "gui/$(id -u)/${AGENT_LABEL}"
  sleep 1
  do_status
}

do_pause() {
  require_user
  command mkdir -p "$(dirname "${PAUSED_FILE}")"
  : > "${PAUSED_FILE}"
  echo "Paused: a lid close does not lock until 'mac_lid_lock.sh resume'."
}

do_resume() {
  require_user
  command rm -f "${PAUSED_FILE}"
  echo "Resumed: a lid close locks the screen."
}

require_macos

cmd="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "${cmd}" in
  install)
    do_install
    ;;
  uninstall)
    do_uninstall
    ;;
  restart)
    do_restart
    ;;
  status)
    do_status
    ;;
  pause)
    do_pause
    ;;
  resume)
    do_resume
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
