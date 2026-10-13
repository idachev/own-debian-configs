#!/bin/bash
# Install a user LaunchAgent that keeps the worca web UI running
# (http://localhost:4317). It starts at login and comes back after a crash.
#
# Usage:
#   worca_ui_agent.sh install
#   worca_ui_agent.sh uninstall
#   worca_ui_agent.sh restart
#   worca_ui_agent.sh status
#   worca_ui_agent.sh print-plist
#
# RunAtLoad + KeepAlive=true. `worca ui start` exits 0 even when its server
# dies, so KeepAlive must be unconditional. Because of that, `worca ui stop`
# only stops the UI for ~10 s; use `uninstall` to stop it for good.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

AGENT_LABEL="${AGENT_LABEL:-com.idachev.worca-ui}"
AGENT_PLIST="${AGENT_PLIST:-${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist}"
AGENT_LOG="${AGENT_LOG:-${HOME}/Library/Logs/worca-ui.log}"
WORCA_BIN_DEFAULT="/opt/homebrew/bin/worca"
# ~/.local/bin holds `claude`, which worca starts for its agents.
LAUNCHD_PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

usage() {
  cat <<EOF
Usage:
  worca_ui_agent.sh install
  worca_ui_agent.sh uninstall
  worca_ui_agent.sh restart
  worca_ui_agent.sh status
  worca_ui_agent.sh print-plist

install loads a user LaunchAgent (Aqua, RunAtLoad, KeepAlive) that runs
\`worca ui start\`. Stop a UI that is already running before install.
status exits 0 only when the agent is installed, loaded, and the UI answers.
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

worca_bin() {
  echo "${WORCA_BIN:-${WORCA_BIN_DEFAULT}}"
}

require_worca() {
  local bin
  bin="$(worca_bin)"
  if [ ! -x "${bin}" ]; then
    echo "worca missing or not executable: ${bin}" >&2
    exit 1
  fi
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
    <string>$(worca_bin)</string>
    <string>ui</string>
    <string>start</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${LAUNCHD_PATH}</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
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
  # bootout returns before the job is gone; bootstrap then fails with exit 5.
  local i
  for i in $(seq 1 20); do
    job_loaded "${target}" || return 0
    sleep 0.5
  done
  echo "WARNING: ${target} still loaded after bootout." >&2
}

do_status() {
  local id target bin plist_state loaded ui_state ok=0
  id="$(uid)"
  target="gui/${id}/${AGENT_LABEL}"
  bin="$(worca_bin)"

  if [ -x "${bin}" ]; then
    echo "worca:     ${bin} (present)"
  else
    echo "worca:     ${bin} (missing)"
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

  if [ -x "${bin}" ] && PATH="${LAUNCHD_PATH}" "${bin}" ui status >/dev/null 2>&1; then
    ui_state="running"
  else
    ui_state="not running"
    ok=1
  fi
  echo "ui:        ${ui_state}"
  echo "log:       ${AGENT_LOG}"

  return "${ok}"
}

do_install() {
  local id target
  require_worca
  write_agent_plist
  id="$(uid)"
  target="gui/${id}/${AGENT_LABEL}"
  launchctl enable "${target}"
  bootout_if_loaded "${target}"
  launchctl bootstrap "gui/${id}" "${AGENT_PLIST}"
  echo "Installed LaunchAgent ${AGENT_LABEL}"
  echo "Log: ${AGENT_LOG}"
  # The UI needs a few seconds to bind its port.
  sleep 5
  do_status
}

do_uninstall() {
  local id target
  id="$(uid)"
  target="gui/${id}/${AGENT_LABEL}"
  if [ -f "${AGENT_PLIST}" ] || job_loaded "${target}"; then
    launchctl disable "${target}"
    bootout_if_loaded "${target}"
  fi
  command rm -f "${AGENT_PLIST}"
  echo "Removed LaunchAgent ${AGENT_LABEL}"
}

do_restart() {
  local id
  id="$(uid)"
  launchctl kickstart -k "gui/${id}/${AGENT_LABEL}"
  sleep 5
  do_status
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
  restart)
    do_restart
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
