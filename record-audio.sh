#!/usr/bin/env bash
#
# record-audio.sh — record what's playing out of your sound card (or your mic)
#
# Usage:
#   record-audio.sh             Record system playback (default output monitor)
#   record-audio.sh -m          Record the microphone (default input) instead
#   record-audio.sh -b          Record BOTH mic + system playback, mixed (needs ffmpeg)
#   record-audio.sh -d DEVICE   Record from an explicit PulseAudio source
#   record-audio.sh -o FILE     Write to FILE instead of ~/recording-<timestamp>.wav
#   record-audio.sh -l          List available sources and exit
#
# Stop recording with Ctrl-C. Output is a WAV file.

set -euo pipefail

mode="playback"
device=""
outfile=""

while getopts "mbd:o:lh" opt; do
  case "$opt" in
    m) mode="mic" ;;
    b) mode="both" ;;
    d) device="$OPTARG" ;;
    o) outfile="$OPTARG" ;;
    l) pactl list short sources; exit 0 ;;
    h|*)
      command grep -E '^#( |$)' "$0" | command sed 's/^# \{0,1\}//'
      exit 0 ;;
  esac
done

default_sink=$(pactl get-default-sink)
default_source=$(pactl get-default-source)

# "both" mode mixes the mic and the playback monitor with ffmpeg.
if [[ "$mode" == "both" ]]; then
  command -v ffmpeg >/dev/null || { echo "ffmpeg is required for -b (both) mode" >&2; exit 1; }
  monitor="${default_sink}.monitor"
  mic="$default_source"
  if [[ -z "$outfile" ]]; then
    outfile="$HOME/recording-$(date +%Y%m%d-%H%M%S).wav"
  fi
  echo "Recording playback: $monitor"
  echo "Recording mic:      $mic"
  echo "Writing to:         $outfile"
  echo "Press Ctrl-C to stop."
  # normalize=0 keeps both at full volume (mic stays audible over system audio).
  exec ffmpeg -hide_banner -loglevel warning -stats \
    -f pulse -i "$monitor" \
    -f pulse -i "$mic" \
    -filter_complex "amix=inputs=2:duration=longest:normalize=0" \
    "$outfile"
fi

# Resolve the device if not given explicitly.
if [[ -z "$device" ]]; then
  if [[ "$mode" == "mic" ]]; then
    device="$default_source"
  else
    # The ".monitor" source captures whatever the sink is playing.
    device="${default_sink}.monitor"
  fi
fi

# Verify the source actually exists; fail early with a helpful list.
if ! pactl list short sources | command grep -qF "$device"; then
  echo "Source not found: $device" >&2
  echo "Available sources:" >&2
  pactl list short sources | command awk '{print "  " $2}' >&2
  exit 1
fi

if [[ -z "$outfile" ]]; then
  outfile="$HOME/recording-$(date +%Y%m%d-%H%M%S).wav"
fi

echo "Recording from: $device"
echo "Writing to:     $outfile"
echo "Press Ctrl-C to stop."

exec parecord --device="$device" --file-format=wav "$outfile"
