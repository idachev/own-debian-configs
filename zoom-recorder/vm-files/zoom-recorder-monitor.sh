#!/usr/bin/env bash
# Background monitor: auto-start a recording when a Zoom meeting is detected,
# and start a fresh one if the previous recording dies mid-meeting.
#
# Started by ~/.config/autostart/zoom-recorder-monitor.desktop when XFCE boots.
# Logs to ~/recordings/.monitor.log
# Pause/resume via the "Auto-Record" desktop toggle (touches the flag file).

set -uo pipefail

TICK="${ZOOM_MON_TICK:-5}"                       # seconds between checks
REC_DIR="$HOME/recordings"
PID_FILE="$REC_DIR/.current.pid"
PAUSE_FLAG="$REC_DIR/.monitor.paused"
SELF_PID="$REC_DIR/.monitor.pid"
SELF_LOCK="$REC_DIR/.monitor.lock"
LOG="$REC_DIR/.monitor.log"
START_SCRIPT="$HOME/bin/zoom-record-start.sh"

mkdir -p "$REC_DIR"

# Hold an exclusive flock for the lifetime of the monitor. Prevents two
# instances racing past the PID-file check from autostart + manual launch.
exec 8>"$SELF_LOCK"
if ! flock -n 8; then
  printf '[%s] another monitor instance is starting; exiting\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG"
  exit 0
fi

export DISPLAY=:1
[[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && \
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# Refuse to run twice — keep only one monitor instance.
if [[ -f "$SELF_PID" ]] && kill -0 "$(cat "$SELF_PID")" 2>/dev/null; then
  log "monitor already running as PID $(cat "$SELF_PID"); exiting"
  exit 0
fi
echo $$ > "$SELF_PID"
trap 'rm -f "$SELF_PID"' EXIT

# Returns 0 if we believe a Zoom meeting is in progress.
# Multiple signals — any one triggers detection.
in_meeting() {
  # Signal 1: window titles that ONLY appear during a meeting.
  #   - "Zoom Meeting" / "Zoom Workplace": main meeting window
  #   - zoom_linux_float_video_window: PiP video when main window is hidden
  #   - as_toolbar: floating meeting toolbar
  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -l 2>/dev/null | grep -iE \
      'zoom meeting|zoom workplace|zoom_linux_float_video_window|as_toolbar' \
      >/dev/null && return 0
  fi
  # Signal 2: active Zoom audio stream (e.g. "ZOOM VoiceEngine" in a meeting).
  if command -v pactl >/dev/null 2>&1; then
    pactl list sink-inputs 2>/dev/null \
      | grep -iE 'application\.(name|process\.binary) = "?(zoom|ZoomLauncher|ZOOM VoiceEngine)' \
      >/dev/null && return 0
  fi
  # Signal 3: Zoom meeting helper process (cpthost) — only spawned in meetings.
  pgrep -f '/opt/zoom/cpthost' >/dev/null && return 0
  return 1
}

is_recording() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

log "monitor started, tick=${TICK}s, pid=$$"

while true; do
  if [[ -f "$PAUSE_FLAG" ]]; then
    sleep "$TICK"
    continue
  fi

  if in_meeting && ! is_recording; then
    log "Zoom meeting detected and no recording running — starting"
    if [[ -x "$START_SCRIPT" ]]; then
      "$START_SCRIPT" >/dev/null 2>&1 || log "start script failed"
    else
      log "ERROR: $START_SCRIPT missing or not executable"
    fi
  fi

  sleep "$TICK"
done
