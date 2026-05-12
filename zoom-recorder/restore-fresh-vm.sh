#!/usr/bin/env bash
# One-shot bootstrap of a freshly-launched recorder VM.
# Runs end-to-end: rsync repo → setup-vm.sh → restore state tarball →
# Tailscale auth → health-check. Idempotent — safe to re-run.
#
# Usage:
#   ./restore-fresh-vm.sh                           # picks newest tarball in $HOME
#   ./restore-fresh-vm.sh ~/path/to/backup.tar.gz   # specific tarball
#   ZOOM_VM_HOST=other-alias ./restore-fresh-vm.sh
#
# Prereqs on this laptop:
#   - new EC2 instance launched
#   - ~/.ssh/config HostName for `zoom-recorder-aws` updated to its new IP
#   - SSH key already accepted (try `ssh zoom-recorder-aws true` first)

set -euo pipefail

HOST="${ZOOM_VM_HOST:-zoom-recorder-aws}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="${1:-}"

# Resolve latest tarball if none passed. Missing tarball is not fatal —
# the orchestrator just skips the restore step (fresh setup mode).
# Search the canonical data/ dir first, then $HOME (legacy location).
if [[ -z "$TARBALL" ]]; then
  TARBALL="$(ls -t \
    "$SCRIPT_DIR"/data/zoom-recorder-vm-state-*.tar.gz \
    "$HOME"/zoom-recorder-vm-state-*.tar.gz \
    2>/dev/null | head -1 || true)"
  if [[ -n "$TARBALL" ]]; then
    echo "Using latest backup: $TARBALL"
  fi
fi
if [[ -n "$TARBALL" && ! -r "$TARBALL" ]]; then
  echo "Cannot read $TARBALL" >&2; exit 1
fi

step()  { printf '\n\033[1;36m==> Step %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }

# ---------------------------------------------------------------------------
step "1/6 — SSH reachability to $HOST"
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" 'echo OK >/dev/null'; then
  echo "ERROR: ssh $HOST failed."
  echo "Check ~/.ssh/config HostName matches the new EC2 public IP."
  exit 1
fi
echo "  ssh OK"

# ---------------------------------------------------------------------------
step "2/6 — rsync zoom-recorder/ to the VM"
rsync -avz --delete \
  --exclude '.git' --exclude 'tmp' \
  "$SCRIPT_DIR/" \
  "$HOST:~/zoom-recorder/" | tail -n 5

# ---------------------------------------------------------------------------
step "3/6 — run setup-vm.sh on the VM (apt updates + installs — ~10 min)"
echo "  output streamed below; full log on VM at /tmp/setup-vm-*.log"
ssh -t "$HOST" 'cd ~/zoom-recorder && ./setup-vm.sh 2>&1 | tee /tmp/setup-vm-$(date +%Y%m%d-%H%M%S).log'

# ---------------------------------------------------------------------------
if [[ -n "$TARBALL" ]]; then
  step "4/6 — restore state tarball ($TARBALL)"
  "$SCRIPT_DIR/restore-vm-state.sh" "$TARBALL"
else
  step "4/6 — SKIPPED (no backup tarball found; fresh setup)"
  warn "Manual follow-ups you'll need to do after this script finishes:"
  warn "  1. Configure rclone gdrive (one-time OAuth flow):"
  warn "       ssh $HOST"
  warn "       rclone config        # add remote 'gdrive', backend 'drive', scope 3"
  warn "  2. Tell the recorder to use it:"
  warn "       ssh $HOST 'mkdir -p ~/.config/environment.d &&"
  warn "         echo ZOOM_REC_REMOTE=gdrive:ZoomRecordings > ~/.config/environment.d/zoom-recorder.conf &&"
  warn "         systemctl --user set-environment ZOOM_REC_REMOTE=gdrive:ZoomRecordings'"
  warn "  3. The VNC password is in ~/.config/tigervnc/.passwd-plain on the VM:"
  warn "       ssh $HOST cat .config/tigervnc/.passwd-plain"
fi

# ---------------------------------------------------------------------------
step "5/6 — Tailscale auth (interactive)"
if ssh "$HOST" 'sudo tailscale status' 2>/dev/null | grep -qE '^100\.'; then
  echo "  already authenticated: $(ssh "$HOST" 'sudo tailscale ip -4')"
else
  echo "  starting 'tailscale up --qr' in background; URL will appear below."
  ssh "$HOST" '> /tmp/tailscale-up.log; sudo nohup tailscale up --qr </dev/null >/tmp/tailscale-up.log 2>&1 & disown'
  sleep 4
  ssh "$HOST" 'cat /tmp/tailscale-up.log'
  echo
  read -r -p "Press Enter once you've completed the auth in the browser... " _
  ssh "$HOST" 'sudo tailscale status' | head -n 3
fi

# ---------------------------------------------------------------------------
step "6/6 — health check"
"$SCRIPT_DIR/health-check.sh"

echo
echo "Done. Open VNC to $HOST and join a Zoom meeting; the monitor will auto-record."
