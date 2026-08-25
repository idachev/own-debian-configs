#!/bin/bash
# Cut the laptop backlight while the lid is closed.
# Cinnamon lock keeps the panel on (lock UI + DPMS disabled).
# Do not replace Cinnamon with i3lock; this only drives intel_backlight.

[ "$1" = -x ] && shift && set -x

set -euo pipefail

BACKLIGHT=/sys/class/backlight/intel_backlight/brightness
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lid-blank-panel"
STATE_FILE="$STATE_DIR/brightness"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/lid-blank-panel.lock"

command mkdir -p "$STATE_DIR"

exec 9>"$LOCK_FILE"
if ! command flock -n 9; then
  echo "lid-blank-panel already running" >&2
  exit 0
fi

lid_closed() {
  command busctl get-property org.freedesktop.UPower /org/freedesktop/UPower \
    org.freedesktop.UPower LidIsClosed 2>/dev/null | command grep -q 'true'
}

blank() {
  if [ ! -f "$STATE_FILE" ]; then
    command cat "$BACKLIGHT" >"$STATE_FILE"
  fi
  command printf '0\n' >"$BACKLIGHT"
}

unblank() {
  if [ -f "$STATE_FILE" ]; then
    command cat "$STATE_FILE" >"$BACKLIGHT"
    command rm -f "$STATE_FILE"
  fi
}

sync_to_lid() {
  if lid_closed; then
    blank
  else
    unblank
  fi
}

sync_to_lid

while IFS= read -r line; do
  case "$line" in
    *"LidIsClosed': <true>"*) blank ;;
    *"LidIsClosed': <false>"*) unblank ;;
  esac
done < <(exec /usr/bin/gdbus monitor --system --dest org.freedesktop.UPower \
  --object-path /org/freedesktop/UPower 9>&-)
