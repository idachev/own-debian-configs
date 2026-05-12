#!/usr/bin/env bash
# Local helper: ssh into the recorder VM and print a one-screen health
# summary. Useful right after a fresh setup-vm.sh run, after a reboot, or
# when something feels off mid-session.
#
# Usage:
#   ./health-check.sh                            # default host: zoom-recorder-aws
#   ZOOM_VM_HOST=other-alias ./health-check.sh   # different ssh alias
#
# All checks run in a single ssh round-trip so re-running is cheap.

set -uo pipefail

HOST="${ZOOM_VM_HOST:-zoom-recorder-aws}"

ssh -o BatchMode=yes "$HOST" '
echo "=== system ==="
echo "host      : $(hostname)"
echo "uptime    : $(uptime -p)"
echo "load      : $(uptime | sed "s/.*load average: //")"
echo "free disk : $(df -h "$HOME/recordings" 2>/dev/null | awk "NR==2{print \$4 \" free of \" \$2}")"
echo "linger    : $(loginctl show-user "$USER" 2>/dev/null | grep Linger)"
echo

# Helper: print first match of a pgrep -af pattern, or NONE if empty.
# Pipelines like `pgrep | grep | head | cut` always exit 0 because the
# tail of the pipe gets empty input and succeeds, so `|| echo NONE`
# never fires. Capture into a var and use parameter expansion.
_first() {
  local pattern="$1" width="${2:-90}" out
  out=$(pgrep -af "$pattern" 2>/dev/null | grep -v grep | head -1 | cut -c1-"$width")
  printf "%s" "${out:-NONE}"
}

echo "=== display / X / audio ==="
echo "vncserver : $(systemctl --user is-active vncserver@:1) (NRestarts=$(systemctl --user show -p NRestarts --value vncserver@:1))"
echo "Xvnc      : $(_first Xtigervnc 95)"
_listen=$(ss -tln 2>/dev/null | grep 5901 | head -1); echo "5901      : ${_listen:-no listener}"
echo "display   : $(DISPLAY=:1 xdpyinfo 2>/dev/null | awk "/dimensions:/{print \$2}")"
echo "sinks     : $(pactl list short sinks 2>/dev/null | grep -c zoom_sink) zoom_sink module(s)"
echo

echo "=== recorder daemons ==="
echo "monitor   : $(_first zoom-recorder-monitor.sh)"
echo "uploader  : $(_first zoom-recorder-uploader.sh)"
echo "inotify   : $(_first inotifywait)"
echo "monitor paused?  $([ -f ~/recordings/.monitor.paused ] && echo YES || echo no)"
echo

echo "=== recording / Zoom state ==="
echo "in meeting? $(wmctrl -l 2>/dev/null | grep -iqE "zoom meeting|zoom_linux_float|as_toolbar" && echo YES || echo no)"
echo "ffmpeg     : $(_first "^ffmpeg .*x11grab")"
echo "current pid: $(cat ~/recordings/.current.pid 2>/dev/null || echo none)"
echo "current base: $(cat ~/recordings/.current.base 2>/dev/null || echo none)"
echo

echo "=== cloud upload ==="
echo "env       : $(systemctl --user show-environment | grep ZOOM_REC_REMOTE || echo "ZOOM_REC_REMOTE not set")"
echo "rclone    : $(rclone listremotes 2>/dev/null | tr "\n" " " || echo "rclone missing")"
echo "tailscale : $(sudo tailscale ip -4 2>/dev/null || echo "not authed")"
mp4=$(ls ~/recordings/recording-*-part*.mp4 2>/dev/null | wc -l)
marked=$(ls ~/recordings/recording-*-part*.mp4.uploaded 2>/dev/null | wc -l)
echo "files     : $mp4 mp4 / $marked marked uploaded"
echo

echo "=== monitor log (last 3) ==="
tail -n 3 ~/recordings/.monitor.log 2>/dev/null || echo "(no log)"
echo

echo "=== uploader log (last 3 events) ==="
tail -n 30 ~/recordings/.uploader.log 2>/dev/null \
  | grep -E "^\[|uploader started|Copied \(new\)|FAILED" \
  | tail -n 3 \
  || echo "(no log)"
'
