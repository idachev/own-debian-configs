#!/usr/bin/env bash
# Toggle the auto-record monitor on/off by creating/removing a flag file.
# When OFF, the monitor stays running but does not start recordings.

set -uo pipefail

REC_DIR="$HOME/recordings"
PAUSE_FLAG="$REC_DIR/.monitor.paused"
mkdir -p "$REC_DIR"

export DISPLAY=:1
[[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && \
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

notify() {
  notify-send -t 4000 -i "${2:-emblem-default}" "Auto-Record" "$1" 2>/dev/null || true
  logger -t zoom-recorder "$1"
}

if [[ -f "$PAUSE_FLAG" ]]; then
  rm -f "$PAUSE_FLAG"
  notify "Auto-Record: ON" "media-record"
else
  touch "$PAUSE_FLAG"
  notify "Auto-Record: OFF" "media-playback-pause"
fi
