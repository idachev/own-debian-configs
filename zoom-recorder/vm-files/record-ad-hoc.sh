#!/usr/bin/env bash
# Ad-hoc Zoom recording from a terminal (foreground, Ctrl-C to stop).
# For the icon-driven workflow use zoom-record-start.sh / zoom-record-stop.sh instead.
# Installed location: ~/bin/record-ad-hoc.sh

set -euo pipefail

NAME="${1:-recording-$(date +%Y%m%d-%H%M%S)}"
REC_DIR="$HOME/recordings"
SEGMENT_SECONDS="${ZOOM_SEGMENT_SECONDS:-900}"
mkdir -p "$REC_DIR"

pulseaudio --start 2>/dev/null || true
pactl list short sinks 2>/dev/null | grep -q 'zoom_sink' || \
  pactl load-module module-null-sink \
    sink_name=zoom_sink \
    sink_properties=device.description=ZoomSink >/dev/null
pactl set-default-sink zoom_sink 2>/dev/null || true

VIDEO_SIZE=$(xdpyinfo -display :1 2>/dev/null | awk '/dimensions:/{print $2; exit}')
if [[ -z "$VIDEO_SIZE" ]]; then
  echo "ERROR: cannot detect framebuffer size (xdpyinfo missing or X11 :1 down)." >&2
  exit 1
fi

MINS=$(( SEGMENT_SECONDS / 60 ))
echo "Recording session: $NAME  (size: $VIDEO_SIZE, parts every ${MINS} min)"
echo "Output: $REC_DIR/${NAME}-part%03d.mp4"
echo "Press Ctrl-C to stop."
echo

ffmpeg -hide_banner \
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
  "$REC_DIR/${NAME}-part%03d.mp4"
