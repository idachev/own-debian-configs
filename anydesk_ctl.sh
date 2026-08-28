#!/bin/bash
# Start or stop AnyDesk and its macOS launchd jobs.
#
# Usage:
#   anydesk_ctl.sh start
#   anydesk_ctl.sh stop
#   anydesk_ctl.sh status
#
# stop disables launchd jobs so they do not start after reboot.
# start enables the jobs and opens the app.
# System service plists exist only if unattended access was installed.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

APP="/Applications/AnyDesk.app"
BUNDLE_ID="com.philandro.anydesk"
PROC_PATTERN='/Applications/AnyDesk.app'

usage() {
  cat <<EOF
Usage:
  anydesk_ctl.sh start
  anydesk_ctl.sh stop
  anydesk_ctl.sh status

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
  id -u
}

anydesk_plists() {
  local old plists
  old="$(shopt -p nullglob)"
  shopt -s nullglob
  plists=(
    /Library/LaunchDaemons/com.philandro.anydesk*.plist
    /Library/LaunchAgents/com.philandro.anydesk*.plist
  )
  eval "$old"
  if [ ${#plists[@]} -gt 0 ]; then
    printf '%s\n' "${plists[@]}"
  fi
}

anydesk_needs_sudo() {
  local old plists
  old="$(shopt -p nullglob)"
  shopt -s nullglob
  plists=(/Library/LaunchDaemons/com.philandro.anydesk*.plist)
  eval "$old"
  [ ${#plists[@]} -gt 0 ]
}

plist_label() {
  /usr/libexec/PlistBuddy -c 'Print :Label' "$1" 2>/dev/null || true
}

plist_domain() {
  case "$1" in
    /Library/LaunchDaemons/*) echo system ;;
    *) echo "gui/$(uid)" ;;
  esac
}

need_sudo() {
  if ! sudo -v; then
    echo "sudo is required to change system launchd jobs." >&2
    exit 1
  fi
}

job_loaded() {
  launchctl print "$1" >/dev/null 2>&1
}

stop_job() {
  local plist="$1"
  local label domain target
  label="$(plist_label "$plist")"
  domain="$(plist_domain "$plist")"
  [ -n "$label" ] || return 0
  target="${domain}/${label}"
  if [ "$domain" = system ]; then
    sudo launchctl disable "$target" || true
    if job_loaded "$target"; then
      sudo launchctl bootout "$target" || true
    fi
  else
    launchctl disable "$target" || true
    if job_loaded "$target"; then
      launchctl bootout "$target" || true
    fi
  fi
}

start_job() {
  local plist="$1"
  local label domain target
  label="$(plist_label "$plist")"
  domain="$(plist_domain "$plist")"
  [ -n "$label" ] || return 0
  target="${domain}/${label}"
  if [ "$domain" = system ]; then
    sudo launchctl enable "$target" || true
    if job_loaded "$target"; then
      sudo launchctl kickstart -k "$target" || true
    else
      sudo launchctl bootstrap system "$plist" || true
      sudo launchctl kickstart "$target" || true
    fi
  else
    launchctl enable "$target" || true
    if job_loaded "$target"; then
      launchctl kickstart -k "$target" || true
    else
      launchctl bootstrap "$domain" "$plist" || true
      launchctl kickstart "$target" || true
    fi
  fi
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
  pkill -TERM -f "$PROC_PATTERN" 2>/dev/null || true
  sleep 1
  pkill -KILL -f "$PROC_PATTERN" 2>/dev/null || true
}

assert_stopped() {
  if pgrep -f "$PROC_PATTERN" >/dev/null 2>&1; then
    echo "WARNING: AnyDesk processes still running:" >&2
    pgrep -lf "$PROC_PATTERN" >&2 || true
    exit 1
  fi
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

job_state() {
  local plist="$1"
  local label domain target loaded override
  label="$(plist_label "$plist")"
  domain="$(plist_domain "$plist")"
  [ -n "$label" ] || return 0
  target="${domain}/${label}"
  if job_loaded "$target"; then
    loaded=loaded
  else
    loaded="not loaded"
  fi
  override="$(disabled_state "$domain" "$label")"
  echo "    $target  $loaded  $override"
}

do_stop() {
  local plist plists
  require_macos
  require_app
  plists="$(anydesk_plists || true)"
  if [ -n "$plists" ]; then
    if anydesk_needs_sudo; then
      need_sudo
    fi
    echo "Disabling AnyDesk launchd jobs..."
    while IFS= read -r plist; do
      [ -n "$plist" ] || continue
      echo "  stop $plist"
      stop_job "$plist"
    done <<<"$plists"
  fi
  echo "Quitting AnyDesk..."
  quit_gui
  kill_leftovers
  assert_stopped
  echo "AnyDesk stopped."
}

do_start() {
  local plist plists
  require_macos
  require_app
  plists="$(anydesk_plists || true)"
  if [ -n "$plists" ]; then
    if anydesk_needs_sudo; then
      need_sudo
    fi
    echo "Enabling AnyDesk launchd jobs..."
    while IFS= read -r plist; do
      [ -n "$plist" ] || continue
      echo "  start $plist"
      start_job "$plist"
    done <<<"$plists"
  fi
  echo "Opening AnyDesk..."
  open -a AnyDesk
  echo "AnyDesk started."
}

do_status() {
  local ver plist plists
  require_macos
  echo "AnyDesk"
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
  plists="$(anydesk_plists || true)"
  if [ -z "$plists" ]; then
    echo "  launchd: none (service not installed)"
  else
    echo "  launchd:"
    while IFS= read -r plist; do
      [ -n "$plist" ] || continue
      job_state "$plist"
    done <<<"$plists"
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
