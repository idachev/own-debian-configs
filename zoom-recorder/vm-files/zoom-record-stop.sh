#!/usr/bin/env bash
# Stop the active Zoom recording on the VM.
# Sends SIGINT so ffmpeg finalizes the mp4 header.
# Installed location: ~/bin/zoom-record-stop.sh
# Launched from: ~/Desktop/zoom-record-stop.desktop

set -uo pipefail

REC_DIR="$HOME/recordings"
PID_FILE="$REC_DIR/.current.pid"
BASE_FILE="$REC_DIR/.current.base"

export DISPLAY=:1
[[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && \
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

notify() {
  notify-send -t 6000 -i "${2:-media-playback-stop}" "Zoom Recorder" "$1" 2>/dev/null || true
  logger -t zoom-recorder "$1"
}

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

if ! is_running; then
  notify "Not recording." "dialog-warning"
  rm -f "$PID_FILE" "$BASE_FILE"
  exit 0
fi

PID=$(cat "$PID_FILE")
notify "Stopping..." "media-playback-stop"
kill -INT "$PID" 2>/dev/null || true

# Wait up to 15s for graceful shutdown
for _ in {1..30}; do
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.5
done

if kill -0 "$PID" 2>/dev/null; then
  kill -KILL "$PID" 2>/dev/null || true
  notify "Force-killed ffmpeg (last segment may be truncated)" "dialog-warning"
fi
rm -f "$PID_FILE"

# Identify all parts of THIS recording session via the saved base name.
BASE="$(cat "$BASE_FILE" 2>/dev/null || true)"
rm -f "$BASE_FILE"

if [[ -z "$BASE" ]]; then
  # Fallback: pick the most recent mp4
  LAST=$(ls -t "$REC_DIR"/*.mp4 2>/dev/null | command head -n 1 || true)
  if [[ -z "$LAST" || ! -f "$LAST" ]]; then
    notify "Stopped but no file found?" "dialog-error"
    exit 1
  fi
  SIZE=$(du -h "$LAST" | cut -f1)
  notify "Saved: $(basename "$LAST") ($SIZE)" "emblem-default"
  exit 0
fi

# Map the segmented output back to a single recording session.
shopt -s nullglob
PARTS=( "$REC_DIR/${BASE}-part"*.mp4 )
shopt -u nullglob

if (( ${#PARTS[@]} == 0 )); then
  notify "Stopped but no parts found for $BASE" "dialog-error"
  exit 1
fi

COUNT=${#PARTS[@]}
TOTAL=$(du -ch "${PARTS[@]}" | tail -1 | cut -f1)
notify "Saved $COUNT part(s), $TOTAL total — $BASE" "emblem-default"

# Upload is handled out-of-band by ~/bin/zoom-recorder-uploader.sh, which
# watches $REC_DIR for close_write events and uploads each finalized
# segment as it lands (including the last one when ffmpeg exits cleanly
# from this script's SIGINT). The uploader publishes its own toasts.
