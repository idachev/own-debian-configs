#!/usr/bin/env bash
# Restore a state tarball produced by backup-vm-state.sh onto a fresh
# recorder VM that has already been provisioned with setup-vm.sh.
#
# Usage:
#   ./restore-vm-state.sh ~/zoom-recorder-vm-state-YYYYMMDD-HHMMSS.tar.gz
#   ZOOM_VM_HOST=other-alias ./restore-vm-state.sh path/to/backup.tgz

set -euo pipefail

HOST="${ZOOM_VM_HOST:-zoom-recorder-aws}"
TARBALL="${1:?Usage: $(basename "$0") <backup.tar.gz>}"

[[ -r "$TARBALL" ]] || { echo "Cannot read $TARBALL" >&2; exit 1; }

echo "Restoring $TARBALL → $HOST"
echo

# Push and extract atomically — anything missing in the tar simply isn't
# touched on the remote.
cat "$TARBALL" | ssh -o BatchMode=yes "$HOST" '
set -e
cd $HOME

# Backstop the existing state in case the restore goes sideways.
SAFETY="$HOME/.config/zoom-recorder-pre-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY"
for p in .config/rclone .config/tigervnc/passwd .config/tigervnc/.passwd-plain .config/environment.d; do
  [[ -e "$p" ]] && cp -a --parents "$p" "$SAFETY/" 2>/dev/null || true
done
echo "Pre-restore state preserved at: $SAFETY"

tar xzf -
echo "Tarball extracted into $HOME"

# Permission hygiene — tarballs over ssh sometimes lose modes.
chmod 600 .config/rclone/rclone.conf            2>/dev/null || true
chmod 600 .config/tigervnc/passwd               2>/dev/null || true
chmod 600 .config/tigervnc/.passwd-plain        2>/dev/null || true
chmod 600 .config/environment.d/zoom-recorder.conf 2>/dev/null || true

echo
echo "=== verifying restored state ==="
if [[ -f .config/rclone/rclone.conf ]]; then
  rclone listremotes 2>/dev/null || echo "  rclone listremotes failed (token expired? run: rclone config reconnect <remote>:)"
else
  echo "  no rclone config restored"
fi
if [[ -f .config/environment.d/zoom-recorder.conf ]]; then
  echo "  env file: $(cat .config/environment.d/zoom-recorder.conf)"
fi
if [[ -f .config/tigervnc/.passwd-plain ]]; then
  echo "  VNC password restored (see ~/.config/tigervnc/.passwd-plain)"
fi
'

echo
echo "Restore complete. Recommended follow-up on the VM:"
echo "  1. Re-auth Tailscale (it does NOT survive a new instance):"
echo "       ssh $HOST sudo tailscale up --qr"
echo "  2. Push restored env into the running session and bounce VNC:"
echo "       ssh $HOST '"
echo "         systemctl --user import-environment ZOOM_REC_REMOTE \\"
echo "           < <(grep ZOOM_REC_REMOTE ~/.config/environment.d/zoom-recorder.conf)"
echo "         systemctl --user restart vncserver@:1   # kills any open Zoom"
echo "       '"
echo "  3. Run the health-check:"
echo "       ./health-check.sh"
