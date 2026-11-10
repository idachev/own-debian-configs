#!/bin/bash
# Keep ZeroTier connected on macOS. A root LaunchDaemon polls `zerotier-cli info`.
# While it is not ONLINE (OFFLINE, or the service does not answer), it restarts
# the zerotier-one service with an exponential backoff until it connects.
#
# Usage (install, uninstall need sudo):
#   sudo zerotier_watchdog_osx.sh install
#   sudo zerotier_watchdog_osx.sh uninstall
#   zerotier_watchdog_osx.sh status
#   zerotier_watchdog_osx.sh print-plist
#   zerotier_watchdog_osx.sh run          (the daemon loop, started by launchd)
#
# Why a daemon and not a timer: the backoff state lives in the loop. A
# KeepAlive job comes back after a crash.
#
# Backoff: the first restart comes after ZT_WATCHDOG_GRACE_SECS of continuous
# offline. Each next restart waits twice as long (GRACE, 2*GRACE, ... up to
# ZT_WATCHDOG_MAX_SECS). ONLINE resets everything. When the Mac has no default
# route there is nothing to fix, so it does not restart.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

LABEL="${ZT_WATCHDOG_LABEL:-com.idachev.zerotier-watchdog}"
PLIST="${ZT_WATCHDOG_PLIST:-/Library/LaunchDaemons/${LABEL}.plist}"
INSTALL_BIN="${ZT_WATCHDOG_INSTALL_BIN:-/usr/local/bin/zerotier-watchdog-osx.sh}"
LOG_FILE="${ZT_WATCHDOG_LOG:-/var/log/zerotier-watchdog.log}"

ZT_CLI="${ZT_WATCHDOG_CLI:-/usr/local/bin/zerotier-cli}"
ZT_JOB="${ZT_WATCHDOG_JOB:-system/com.zerotier.one}"
CHECK_SECS="${ZT_WATCHDOG_CHECK_SECS:-30}"
GRACE_SECS="${ZT_WATCHDOG_GRACE_SECS:-60}"
MAX_SECS="${ZT_WATCHDOG_MAX_SECS:-300}"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') zerotier-watchdog: $*"
}

require_macos() {
  if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS." >&2
    exit 1
  fi
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo $0 $1" >&2
    exit 1
  fi
}

# Prints ONLINE, TCP_FALLBACK, OFFLINE, or DOWN when the service does not answer.
zt_state() {
  local out state
  out="$("${ZT_CLI}" info 2>/dev/null)" || { echo DOWN; return; }
  state="$(echo "${out}" | awk '{ print $5 }')"
  echo "${state:-DOWN}"
}

has_default_route() {
  route -n get default >/dev/null 2>&1
}

restart_zerotier() {
  # Kills the daemon and starts it again, also when it is dead or hung.
  if [ -n "${ZT_WATCHDOG_RESTART_CMD:-}" ]; then
    bash -c "${ZT_WATCHDOG_RESTART_CMD}"  # test hook
    return
  fi
  launchctl kickstart -k "${ZT_JOB}"
}

next_delay() {
  local delay=$1
  delay=$((delay * 2))
  if [ "${delay}" -gt "${MAX_SECS}" ]; then
    delay="${MAX_SECS}"
  fi
  echo "${delay}"
}

run_loop() {
  local state offline_since=0 next_restart_at=0 delay="${GRACE_SECS}" now
  log "started, check ${CHECK_SECS}s, grace ${GRACE_SECS}s, max backoff ${MAX_SECS}s"
  while true; do
    now=$(date +%s)
    state="$(zt_state)"
    case "${state}" in
      ONLINE|TCP_FALLBACK)
        if [ "${offline_since}" -ne 0 ]; then
          log "recovered: ${state} after $((now - offline_since))s offline"
        fi
        offline_since=0
        delay="${GRACE_SECS}"
        ;;
      *)
        if ! has_default_route; then
          if [ "${offline_since}" -ne 0 ]; then
            log "no default route, wait for the network"
          fi
          offline_since=0
          delay="${GRACE_SECS}"
        else
          if [ "${offline_since}" -eq 0 ]; then
            offline_since="${now}"
            next_restart_at=$((now + GRACE_SECS))
            log "state ${state}, restart in ${GRACE_SECS}s if it stays"
          fi
          if [ "${now}" -ge "${next_restart_at}" ]; then
            log "state ${state} for $((now - offline_since))s, restarting ${ZT_JOB}"
            if ! restart_zerotier; then
              log "restart failed"
            fi
            next_restart_at=$((now + delay))
            log "next restart in ${delay}s if still not ONLINE"
            delay="$(next_delay "${delay}")"
          fi
        fi
        ;;
    esac
    sleep "${CHECK_SECS}"
  done
}

plist_xml() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_BIN}</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>
EOF
}

job_loaded() {
  launchctl print "system/${LABEL}" >/dev/null 2>&1
}

do_install() {
  require_root install
  # launchd runs a root job: the script it runs must be root-owned, not the
  # user-writable copy in ~/bin.
  install -o root -g wheel -m 755 "$0" "${INSTALL_BIN}"
  plist_xml > "${PLIST}"
  chown root:wheel "${PLIST}"
  chmod 644 "${PLIST}"
  if job_loaded; then
    launchctl bootout "system/${LABEL}" || true
  fi
  launchctl bootstrap system "${PLIST}"
  echo "installed ${LABEL}; log: ${LOG_FILE}"
}

do_uninstall() {
  require_root uninstall
  if job_loaded; then
    launchctl bootout "system/${LABEL}" || true
  fi
  command rm -f "${PLIST}" "${INSTALL_BIN}"
  echo "uninstalled ${LABEL}; log kept: ${LOG_FILE}"
}

do_status() {
  local ok=0
  if [ -f "${PLIST}" ]; then echo "plist: ${PLIST}"; else echo "plist: missing"; ok=1; fi
  if job_loaded; then echo "job: loaded"; else echo "job: not loaded"; ok=1; fi
  if [ -f "${LOG_FILE}" ]; then
    echo "log tail (${LOG_FILE}):"
    command tail -n 5 "${LOG_FILE}"
  fi
  exit "${ok}"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  require_macos
  case "${1:-}" in
    install) do_install ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    print-plist) plist_xml ;;
    run) run_loop ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
