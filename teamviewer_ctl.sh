#!/bin/bash
# Start or stop TeamViewer and its macOS launchd jobs.
#
# Usage:
#   teamviewer_ctl.sh start
#   teamviewer_ctl.sh stop
#   teamviewer_ctl.sh status
#
# stop disables the keepalive jobs so they do not start after reboot.
# start re-enables them, restores Start with System, and opens the app.
# Privileged helpers stay installed; they start only on demand.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

APP="/Applications/TeamViewer.app"
BUNDLE_ID="com.teamviewer.TeamViewer"
PROC_PATTERN='/Applications/TeamViewer.app'
START_FLAG="/Library/Application Support/TeamViewer/.startwithsystem"

# label|plist — KeepAlive jobs only. Helper/Uninstaller stay on-demand.
SYSTEM_JOBS=(
  "com.teamviewer.service|/Library/LaunchDaemons/com.teamviewer.teamviewer_service.plist"
)
AQUA_JOBS=(
  "com.teamviewer.teamviewer|/Library/LaunchAgents/com.teamviewer.teamviewer.plist"
)
LOGINWINDOW_JOBS=(
  "com.teamviewer.desktop|/Library/LaunchAgents/com.teamviewer.teamviewer_desktop.plist"
)

usage() {
  cat <<EOF
Usage:
  teamviewer_ctl.sh start
  teamviewer_ctl.sh stop
  teamviewer_ctl.sh status

stop disables launchd jobs so they do not start after reboot.
start enables the jobs and opens the app.
EOF
}

require_macos() {
  if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS." >&2
    exit 1
  fi
}

require_app() {
  if [ ! -d "$APP" ]; then
    echo "Not found: $APP" >&2
    exit 1
  fi
}

uid() {
  if [ "$(id -u)" -ne 0 ]; then
    id -u
    return
  fi
  if [ -n "${SUDO_UID:-}" ]; then
    echo "$SUDO_UID"
    return
  fi
  stat -f %u /dev/console
}

need_sudo() {
  if ! sudo -v; then
    echo "sudo is required to change TeamViewer launchd jobs." >&2
    exit 1
  fi
}

job_loaded() {
  launchctl print "$1" >/dev/null 2>&1
}

# bootout exit 3 = No such process (job gone after the loaded check).
bootout_if_loaded() {
  local target="$1"
  local rc=0
  job_loaded "$target" || return 0
  if [ "${2:-}" = sudo ]; then
    sudo launchctl bootout "$target" || rc=$?
  else
    launchctl bootout "$target" || rc=$?
  fi
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
    echo "WARNING: bootout ${target} failed (exit ${rc})." >&2
    return "$rc"
  fi
}

stop_system_job() {
  local label="$1"
  local plist="$2"
  [ -f "$plist" ] || return 0
  sudo launchctl disable "system/${label}"
  bootout_if_loaded "system/${label}" sudo
  assert_job_disabled system "$label"
}

start_system_job() {
  local label="$1"
  local plist="$2"
  local i
  [ -f "$plist" ] || return 0
  sudo launchctl enable "system/${label}"
  if job_loaded "system/${label}"; then
    sudo launchctl kickstart -k "system/${label}"
  else
    sudo launchctl bootstrap system "$plist"
    for i in 1 2 3 4 5 6 7 8; do
      job_loaded "system/${label}" && break
      sudo launchctl kickstart "system/${label}" 2>/dev/null || true
      sleep 1
    done
  fi
  assert_job_enabled system "$label"
  assert_job_loaded system "$label"
}

stop_aqua_job() {
  local label="$1"
  local plist="$2"
  local id
  id="$(uid)"
  [ -f "$plist" ] || return 0
  launchctl disable "gui/${id}/${label}"
  bootout_if_loaded "gui/${id}/${label}"
  assert_job_disabled "gui/${id}" "$label"
}

start_aqua_job() {
  local label="$1"
  local plist="$2"
  local id i
  id="$(uid)"
  [ -f "$plist" ] || return 0
  launchctl enable "gui/${id}/${label}"
  if job_loaded "gui/${id}/${label}"; then
    launchctl kickstart -k "gui/${id}/${label}"
  else
    launchctl bootstrap "gui/${id}" "$plist"
    for i in 1 2 3 4 5 6 7 8; do
      job_loaded "gui/${id}/${label}" && break
      launchctl kickstart "gui/${id}/${label}" 2>/dev/null || true
      sleep 1
    done
  fi
  assert_job_enabled "gui/${id}" "$label"
  assert_job_loaded "gui/${id}" "$label"
}

# LoginWindow agent. Do not sudo load/unload: as root, load expects LaunchDaemons.
# Do not bootstrap/kickstart into Aqua; LimitLoadToSessionType is LoginWindow.
stop_loginwindow_job() {
  local label="$1"
  local plist="$2"
  local id
  id="$(uid)"
  [ -f "$plist" ] || return 0
  launchctl disable "gui/${id}/${label}"
  bootout_if_loaded "gui/${id}/${label}"
  assert_job_disabled "gui/${id}" "$label"
}

start_loginwindow_job() {
  local label="$1"
  local plist="$2"
  local id
  id="$(uid)"
  [ -f "$plist" ] || return 0
  launchctl enable "gui/${id}/${label}"
  assert_job_enabled "gui/${id}" "$label"
}

is_gui_running() {
  local out
  out="$(osascript -e "application id \"${BUNDLE_ID}\" is running" 2>/dev/null || true)"
  [ "$out" = "true" ]
}

quit_gui() {
  if is_gui_running; then
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
  fi
}

kill_leftovers() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    pgrep -f "$PROC_PATTERN" >/dev/null 2>&1 || return 0
    sleep 1
  done
  if [ "${1:-}" = sudo ]; then
    sudo pkill -TERM -f "$PROC_PATTERN" 2>/dev/null || true
    sleep 1
    sudo pkill -KILL -f "$PROC_PATTERN" 2>/dev/null || true
  else
    pkill -TERM -f "$PROC_PATTERN" 2>/dev/null || true
    sleep 1
    pkill -KILL -f "$PROC_PATTERN" 2>/dev/null || true
  fi
}

assert_stopped() {
  if pgrep -f "$PROC_PATTERN" >/dev/null 2>&1; then
    echo "WARNING: TeamViewer processes still running:" >&2
    pgrep -lf "$PROC_PATTERN" >&2 || true
    exit 1
  fi
}

do_stop() {
  local job label plist
  require_macos
  require_app
  need_sudo
  echo "Disabling TeamViewer launchd jobs..."
  for job in "${SYSTEM_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    echo "  stop system/${label}"
    stop_system_job "$label" "$plist"
  done
  for job in "${AQUA_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    echo "  stop gui/$(uid)/${label}"
    stop_aqua_job "$label" "$plist"
  done
  for job in "${LOGINWINDOW_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    echo "  stop LoginWindow/${label}"
    stop_loginwindow_job "$label" "$plist"
  done
  if [ -e "$START_FLAG" ]; then
    echo "Removing Start with System flag..."
    sudo rm -f "$START_FLAG"
  fi
  echo "Quitting TeamViewer..."
  quit_gui
  kill_leftovers sudo
  assert_stopped
  echo "TeamViewer stopped."
}

do_start() {
  local job label plist
  require_macos
  require_app
  need_sudo
  echo "Enabling TeamViewer launchd jobs..."
  sudo mkdir -p "/Library/Application Support/TeamViewer"
  sudo touch "$START_FLAG"
  for job in "${SYSTEM_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    echo "  start system/${label}"
    start_system_job "$label" "$plist"
  done
  for job in "${AQUA_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    echo "  start gui/$(uid)/${label}"
    start_aqua_job "$label" "$plist"
  done
  for job in "${LOGINWINDOW_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    echo "  enable LoginWindow/${label}"
    start_loginwindow_job "$label" "$plist"
  done
  echo "Opening TeamViewer..."
  open -a TeamViewer
  echo "TeamViewer started."
}

disabled_state() {
  local domain="$1"
  local label="$2"
  local line
  line="$(launchctl print-disabled "$domain" 2>/dev/null | grep -F "\"${label}\"" || true)"
  case "$line" in
    *'=> disabled'*) echo disabled ;;
    *'=> enabled'*) echo enabled ;;
    *) echo default ;;
  esac
}

assert_job_disabled() {
  local domain="$1"
  local label="$2"
  if [ "$(disabled_state "$domain" "$label")" != disabled ]; then
    echo "WARNING: ${domain}/${label} is not disabled." >&2
    return 1
  fi
}

assert_job_enabled() {
  local domain="$1"
  local label="$2"
  if [ "$(disabled_state "$domain" "$label")" = disabled ]; then
    echo "WARNING: ${domain}/${label} is still disabled." >&2
    return 1
  fi
}

assert_job_loaded() {
  local domain="$1"
  local label="$2"
  if ! job_loaded "${domain}/${label}"; then
    echo "WARNING: ${domain}/${label} is not loaded." >&2
    return 1
  fi
}

print_job() {
  local domain="$1"
  local label="$2"
  local plist="$3"
  local extra="${4:-}"
  local target="${domain}/${label}"
  local loaded override
  if [ ! -f "$plist" ]; then
    echo "    $target  plist missing"
    return 0
  fi
  if job_loaded "$target"; then
    loaded=loaded
  else
    loaded="not loaded"
  fi
  override="$(disabled_state "$domain" "$label")"
  if [ -n "$extra" ]; then
    echo "    $target  $loaded  $override  ($extra)"
  else
    echo "    $target  $loaded  $override"
  fi
}

do_status() {
  local ver job label plist
  require_macos
  echo "TeamViewer"
  if [ -d "$APP" ]; then
    ver="$(defaults read "${APP}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
    echo "  app: $APP ($ver)"
  else
    echo "  app: not installed"
  fi
  if pgrep -f "$PROC_PATTERN" >/dev/null 2>&1; then
    echo "  processes:"
    pgrep -lf "$PROC_PATTERN" | sed 's/^/    /'
  else
    echo "  processes: none"
  fi
  echo "  launchd:"
  for job in "${SYSTEM_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    print_job system "$label" "$plist"
  done
  for job in "${AQUA_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    print_job "gui/$(uid)" "$label" "$plist"
  done
  for job in "${LOGINWINDOW_JOBS[@]}"; do
    label="${job%%|*}"
    plist="${job#*|}"
    print_job "gui/$(uid)" "$label" "$plist" "LoginWindow only"
  done
  if [ -e "$START_FLAG" ]; then
    echo "  start-with-system: yes"
  else
    echo "  start-with-system: no"
  fi
}

case "${1:-}" in
  start) do_start ;;
  stop) do_stop ;;
  status) do_status ;;
  -h|--help|help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
