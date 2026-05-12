#!/usr/bin/env bash
# Start a Zoom screen+audio recording on the VM.
# Idempotent: if a recording is already running, notifies and exits.
# Installed location: ~/bin/zoom-record-start.sh
# Launched from: ~/Desktop/zoom-record-start.desktop

set -uo pipefail

REC_DIR="$HOME/recordings"
PID_FILE="$REC_DIR/.current.pid"
BASE_FILE="$REC_DIR/.current.base"
START_LOCK="$REC_DIR/.start.lock"
SEGMENT_SECONDS="${ZOOM_SEGMENT_SECONDS:-900}"   # 15 min chunks by default
mkdir -p "$REC_DIR"

# Serialize concurrent invocations (monitor + manual double-click) so we
# can't race past the is_running guard and spawn two ffmpegs at once.
exec 9>"$START_LOCK"
if ! flock -n 9; then
  echo "Another start in progress" >&2
  exit 0
fi

export DISPLAY=:1
[[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && \
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

notify() {
  notify-send -t 6000 -i "${2:-media-record}" "Zoom Recorder" "$1" 2>/dev/null || true
  logger -t zoom-recorder "$1"
}

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

if is_running; then
  notify "Already recording (PID $(cat "$PID_FILE")). Click Stop first." "dialog-warning"
  exit 0
fi
rm -f "$PID_FILE"

# Ensure PulseAudio + zoom_sink exist
pulseaudio --start 2>/dev/null || true
pactl list short sinks 2>/dev/null | grep -q 'zoom_sink' || \
  pactl load-module module-null-sink \
    sink_name=zoom_sink \
    sink_properties=device.description=ZoomSink >/dev/null
pactl set-default-sink zoom_sink 2>/dev/null || true

NAME="recording-$(date +%Y%m%d-%H%M%S)"
LOG="$REC_DIR/.$NAME.log"
echo "$NAME" > "$BASE_FILE"

# Auto-detect framebuffer size so capture always matches the VNC geometry.
# Fail loud if detection fails — silent fallback to a wrong resolution would
# crop the recording to the top-left corner of a bigger framebuffer.
VIDEO_SIZE=$(xdpyinfo -display :1 2>/dev/null | awk '/dimensions:/{print $2; exit}')
if [[ -z "$VIDEO_SIZE" ]]; then
  notify "Cannot detect framebuffer size — is xdpyinfo installed and X11 :1 up?" "dialog-error"
  rm -f "$BASE_FILE"
  exit 1
fi

# Segment muxer: each $SEGMENT_SECONDS produces a fully-finalized mp4.
# If ffmpeg dies mid-segment only the last partial chunk is affected;
# all earlier parts are intact and playable.
#
# 9>&-  closes start.sh's own flock fd  (.start.lock)
# 8>&-  closes monitor.sh's flock fd if we were invoked by the monitor
#                                     (.monitor.lock). Harmless if absent.
# Without these the kernel keeps both locks held for ffmpeg's whole
# recording lifetime, blocking mid-session restarts of either daemon.
setsid nohup ffmpeg -hide_banner -y -loglevel warning \
  -video_size "$VIDEO_SIZE" -framerate 15 \
  -f x11grab -i :1.0+0,0 \
  -f pulse -i zoom_sink.monitor \
  -c:v libx264 -preset slow -tune stillimage -crf 25 -pix_fmt yuv420p \
  -c:a aac -b:a 96k -ac 2 \
  -f segment \
  -segment_time "$SEGMENT_SECONDS" \
  -reset_timestamps 1 \
  -segment_format mp4 \
  -segment_format_options movflags=+faststart \
  "$REC_DIR/${NAME}-part%03d.mp4" \
  </dev/null > "$LOG" 2>&1 9>&- 8>&- &

echo $! > "$PID_FILE"
sleep 1.5

if is_running; then
  MINS=$(( SEGMENT_SECONDS / 60 ))
  notify "Started: $NAME (parts every ${MINS} min)" "media-record"
else
  notify "FAILED to start. See $LOG" "dialog-error"
  rm -f "$PID_FILE" "$BASE_FILE"
  exit 1
fi
