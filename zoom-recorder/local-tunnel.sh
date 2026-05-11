#!/usr/bin/env bash
# Manage the local SSH tunnel for the VNC port (5901 → VM 5901).
# Lives on the laptop, NOT the VM.
#
# Usage:
#   local-tunnel.sh start    # open backgrounded tunnel (default)
#   local-tunnel.sh stop     # kill the backgrounded tunnel
#   local-tunnel.sh status   # report state
#
# Honours env vars:
#   ZOOM_VM_HOST   SSH alias of the recorder VM (default: zoom-recorder-aws)
#   ZOOM_VNC_PORT  Local port to bind (default: 5901)

set -uo pipefail

HOST="${ZOOM_VM_HOST:-zoom-recorder-aws}"
PORT="${ZOOM_VNC_PORT:-5901}"
CMD="${1:-start}"

# Match the exact backgrounded form started by `start`.
tunnel_pid() {
  pgrep -af "ssh -fN -L ${PORT}:127.0.0.1:${PORT} ${HOST}" \
    | awk '{print $1}' | head -1
}

# Is anything listening on localhost:$PORT (could be us OR an interactive ssh
# session that opened the forward via ~/.ssh/config LocalForward).
port_in_use() {
  ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "(:|\.)${PORT}$"
}

status() {
  local pid; pid=$(tunnel_pid || true)
  if [[ -n "${pid:-}" ]]; then
    echo "UP   (backgrounded tunnel)  PID=${pid}  localhost:${PORT} → ${HOST}:${PORT}"
    return 0
  fi
  if port_in_use; then
    echo "UP   (foreign)  Port ${PORT} is held by another process"
    echo "                — likely an interactive 'ssh ${HOST}' with LocalForward,"
    echo "                  or another VNC tunnel. ${PORT} is reachable either way."
    return 0
  fi
  echo "DOWN  no tunnel"
  return 1
}

start() {
  if [[ -n "$(tunnel_pid || true)" ]]; then
    echo "Tunnel already up."
    status
    return 0
  fi
  if port_in_use; then
    echo "Port ${PORT} already in use (probably an interactive ssh session). Not starting another."
    status
    return 0
  fi
  echo "Opening tunnel to ${HOST}..."
  if ! ssh -fN -L "${PORT}:127.0.0.1:${PORT}" "${HOST}"; then
    echo "ERROR: ssh -fN failed (exit $?). Check that '${HOST}' resolves and key auth works." >&2
    return 1
  fi
  sleep 1
  status
}

stop() {
  local pid; pid=$(tunnel_pid || true)
  if [[ -z "${pid:-}" ]]; then
    echo "No backgrounded tunnel to stop."
    if port_in_use; then
      echo "(But port ${PORT} is still bound by something else — interactive ssh? — left alone.)"
    fi
    return 0
  fi
  kill "$pid"
  echo "Killed tunnel PID ${pid}"
}

case "$CMD" in
  start)         start ;;
  stop)          stop ;;
  status|st|s)   status ;;
  -h|--help|help)
    grep '^#' "$0" | sed -E 's/^# ?//; 1,2d'
    ;;
  *)
    echo "Usage: $(basename "$0") {start|stop|status}" >&2
    exit 2
    ;;
esac
