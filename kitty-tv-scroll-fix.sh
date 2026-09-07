#!/bin/bash
# Make kitty accept TeamViewer wheel events on X11.
#
# TeamViewer injects scroll as XTEST Button 4/5 and disables local pointers.
# kitty 0.46+ ignores Button 4/5 while it still has XI2 scroll devices from
# those local pointers. Adding and removing a master pointer makes kitty
# re-read devices. After that, Button 4/5 work.
#
# Usage:
#   kitty-tv-scroll-fix.sh         # watch TeamViewer sessions (default)
#   kitty-tv-scroll-fix.sh watch
#   kitty-tv-scroll-fix.sh once    # poke XInput now
#   kitty-tv-scroll-fix.sh status

[ "$1" = -x ] && shift && set -x

set -euo pipefail

if [ -d "/run/user/$(command id -u)" ]; then
  LOCK_DIR="/run/user/$(command id -u)"
else
  LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
fi
LOCK_FILE="$LOCK_DIR/kitty-tv-scroll-fix.lock"
POKE_LOCK="$LOCK_DIR/kitty-tv-scroll-fix.poke.lock"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/kitty-tv-scroll-fix.log"
POLL_SEC=2

usage() {
  cat <<EOF
Usage:
  kitty-tv-scroll-fix.sh         watch TeamViewer sessions (default)
  kitty-tv-scroll-fix.sh watch
  kitty-tv-scroll-fix.sh once    poke XInput now
  kitty-tv-scroll-fix.sh status
EOF
}

require_linux_x11() {
  if [ "$(command uname -s)" != Linux ]; then
    echo "This script is for Linux X11." >&2
    exit 1
  fi
  if [ -z "${DISPLAY:-}" ]; then
    export DISPLAY=:0
  fi
  if ! command -v xinput >/dev/null 2>&1; then
    echo "xinput is not installed." >&2
    exit 1
  fi
}

log() {
  echo "kitty-tv-scroll-fix: $*" >&2
  if command -v logger >/dev/null 2>&1; then
    command logger -t kitty-tv-scroll-fix -- "$*" || true
  fi
}

tv_desktop_running() {
  command pgrep -f '/opt/teamviewer/tv_bin/TeamViewer_Desktop' >/dev/null 2>&1
}

# True when the only attached slave pointer is XTEST (TeamViewer grabbed
# local mice: they are floating and disabled). xinput errors are not that.
tv_only_pointers() {
  local listing
  listing=$(command xinput list) || return 1
  ! printf '%s\n' "$listing" | command grep -E '\[slave[[:space:]]+pointer' | command grep -vq XTEST
}

tv_session_ready() {
  tv_desktop_running && tv_only_pointers
}

poke() {
  local prefix
  prefix="kitty-scroll-fix-$$-$RANDOM"

  command mkdir -p "$(command dirname "$POKE_LOCK")"

  if ! (
    exec 8>"$POKE_LOCK"
    command flock 8

    leftover() {
      command xinput list --id-only "${prefix} pointer" 2>/dev/null || true
    }
    cleanup_master() {
      local id
      id=$(leftover)
      if [ -n "$id" ]; then
        command xinput remove-master "$id" Floating >/dev/null 2>&1 || true
      fi
    }
    trap cleanup_master EXIT

    command xinput create-master "$prefix"
    command sleep 0.3
    ptr_id=$(leftover)
    if [ -z "$ptr_id" ]; then
      echo "Failed to create XInput master pointer '$prefix'." >&2
      exit 1
    fi
    command xinput remove-master "$ptr_id" Floating
    command sleep 0.2
    trap - EXIT
  ); then
    return 1
  fi
  log "poked kitty XInput ($prefix)"
}

once() {
  require_linux_x11
  poke
}

watcher_running() {
  exec 9>"$LOCK_FILE"
  if command flock -n 9; then
    command flock -u 9
    return 1
  fi
  return 0
}

status() {
  require_linux_x11
  if watcher_running; then
    echo "watcher: running"
  else
    echo "watcher: not running"
  fi
  if tv_desktop_running; then
    echo "TeamViewer_Desktop: running"
  else
    echo "TeamViewer_Desktop: not running"
  fi
  if tv_only_pointers; then
    echo "pointers: XTEST only"
  else
    echo "pointers: local slave pointer attached"
  fi
}

watch() {
  require_linux_x11
  command mkdir -p "$(command dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  if ! command flock -n 9; then
    echo "kitty-tv-scroll-fix already running" >&2
    exit 0
  fi
  command mkdir -p "$(command dirname "$LOG_FILE")"
  exec >>"$LOG_FILE" 2>&1
  log "watcher started pid=$$ DISPLAY=${DISPLAY:-}"

  local poked=0
  while true; do
    if tv_session_ready; then
      if [ "$poked" -eq 0 ]; then
        if poke; then
          poked=1
        else
          log "poke failed; will retry"
        fi
      fi
    else
      poked=0
    fi
    command sleep "$POLL_SEC"
  done
}

case "${1:-watch}" in
  watch) watch ;;
  once) once ;;
  status) status ;;
  -h | --help | help) usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
