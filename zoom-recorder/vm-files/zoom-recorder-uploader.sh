#!/usr/bin/env bash
# Background uploader: uploads each completed -part*.mp4 to the rclone
# remote as soon as ffmpeg finalizes it (close_write inotify event).
# This means crash-safety isn't just "the previous 15-min part is on
# disk" — it's "the previous 15-min part is already in the cloud".
#
# Started by ~/.config/autostart/zoom-recorder-uploader.desktop with XFCE.
# Logs to ~/recordings/.uploader.log

set -uo pipefail

REC_DIR="$HOME/recordings"
SELF_LOCK="$REC_DIR/.uploader.lock"
SELF_PID="$REC_DIR/.uploader.pid"
LOG="$REC_DIR/.uploader.log"

mkdir -p "$REC_DIR"

export DISPLAY=:1
[[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && \
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Auto-load env (ZOOM_REC_REMOTE) when started outside the XFCE session
# (e.g. via SSH for debugging). systemd's environment.d format is plain
# KEY=VALUE which bash can source — keep that file simple.
if [[ -z "${ZOOM_REC_REMOTE:-}" ]] && \
   [[ -f "$HOME/.config/environment.d/zoom-recorder.conf" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$HOME/.config/environment.d/zoom-recorder.conf"
  set +a
fi

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

notify() {
  # `7>&-` closes the flock fd in the child so a stuck notify-send can't keep
  # holding the lock after the parent dies. `timeout 2` is the second line of
  # defence: if DBus is unreachable (e.g. running from SSH outside the XFCE
  # session), notify-send hangs waiting for a reply — kill it after 2s.
  { timeout 2 notify-send -t 3500 -u low -i "${2:-network-transmit}" \
      "Zoom Recorder Upload" "$1" 2>/dev/null; } 7>&- || true
  { logger -t zoom-recorder-uploader "$1"; } 7>&-
}

# Single instance via flock (kernel releases on death, robust across reboots).
exec 7>"$SELF_LOCK"
if ! flock -n 7; then
  log "another uploader instance is running; exiting"
  exit 0
fi
echo $$ > "$SELF_PID"
trap 'rm -f "$SELF_PID"' EXIT TERM INT

# Preconditions — exit quietly if missing so a fresh VM doesn't spam errors.
if ! command -v rclone >/dev/null 2>&1; then
  log "rclone not installed; exiting"; exit 0
fi
if ! command -v inotifywait >/dev/null 2>&1; then
  log "inotifywait not installed (apt install inotify-tools); exiting"; exit 0
fi
if [[ ! -f "$HOME/.config/rclone/rclone.conf" ]]; then
  log "no rclone config at ~/.config/rclone/rclone.conf; exiting"; exit 0
fi
if [[ -z "${ZOOM_REC_REMOTE:-}" ]]; then
  log "ZOOM_REC_REMOTE not set; exiting"; exit 0
fi

log "uploader started, watching $REC_DIR, remote=$ZOOM_REC_REMOTE"

upload_one() {
  local fname="$1"
  # Filename must match recording-YYYYMMDD-HHMMSS-partNNN.mp4
  if [[ ! "$fname" =~ ^(recording-[0-9]+-[0-9]+)-part[0-9]+\.mp4$ ]]; then
    return 0
  fi
  local base="${BASH_REMATCH[1]}"
  local src="$REC_DIR/$fname"
  local marker="${src}.uploaded"
  local dest="$ZOOM_REC_REMOTE/$base/"

  # Skip if the source vanished (rare race during initial sync vs. cleanup).
  [[ -f "$src" ]] || return 0

  # Skip if we have a marker that's newer than the file — already uploaded.
  # Force re-upload by `rm <file>.uploaded`. The mtime check means a file
  # that was somehow rewritten after upload (rare) will be retransferred.
  if [[ -f "$marker" && "$marker" -nt "$src" ]]; then
    return 0
  fi

  log "uploading $fname  →  $dest"
  # Close fd 7 (the flock) in rclone so a hung rclone can't keep the lock alive.
  if { rclone copy "$src" "$dest" --log-level INFO --log-file "$LOG"; } 7>&-; then
    touch "$marker"
    notify "Uploaded $fname" "emblem-default"
  else
    notify "Upload FAILED: $fname (see .uploader.log)" "dialog-error"
  fi
}

# Initial sync: pick up any segments that already exist on disk but not on
# the remote (e.g. uploader was off when ffmpeg finalized them).
# rclone copy is idempotent: same size = skipped, no wasted bandwidth.
shopt -s nullglob
for f in "$REC_DIR"/recording-*-part*.mp4; do
  upload_one "$(basename "$f")"
done
shopt -u nullglob

# Live watch — close_write fires when ffmpeg rolls to the next segment.
# moved_to covers any rename-into-the-dir cases. -q keeps the log clean.
# Close fd 7 in inotifywait so it doesn't hold the flock for the script's
# entire lifetime in a way that prevents respawn.
{
  inotifywait -m -q -e close_write,moved_to --format '%f' "$REC_DIR" 2>>"$LOG"
} 7>&- | while read -r fname; do
  upload_one "$fname"
done
