#!/usr/bin/env bash
# Tar the unique state from the recorder VM and download it locally so the
# EC2 instance + EBS volume can be torn down. Recordings already live in
# Drive; everything else can be rebuilt by setup-vm.sh + git checkout +
# restore-vm-state.sh on a fresh VM.
#
# Usage:
#   ./backup-vm-state.sh                            # default output filename
#   ./backup-vm-state.sh ~/backups/zoom-recorder.tgz # custom path
#   ZOOM_VM_HOST=other-alias ./backup-vm-state.sh    # different ssh alias
#
# What gets backed up:
#   ~/.config/rclone/                  — gdrive OAuth token
#   ~/.config/tigervnc/passwd          — hashed VNC password
#   ~/.config/tigervnc/.passwd-plain   — plaintext VNC password (mode 600)
#   ~/.config/environment.d/           — ZOOM_REC_REMOTE
#   ~/recordings/*.uploaded            — upload markers (recordings stay on Drive)
#
# Deliberately excluded:
#   ~/.zoom/   — 40+ MB of cache/logs/crash dumps. Sign in fresh on the
#               new VM; takes ~10 s. Set ZOOM_BACKUP_INCLUDE_ZOOM=1 to
#               include sign-in state at the cost of all that cache.
#   ~/.cache/, ~/.local/share/recently-used.xbel etc. — junk
#   ~/.config/tigervnc/{xstartup,config} — recreated by setup-vm.sh
#
# What is NOT backed up (rebuilt by setup-vm.sh + repo checkout):
#   apt packages, ~/bin/, ~/Desktop/, ~/.config/autostart/,
#   ~/.config/systemd/user/, ~/.config/tigervnc/{xstartup,config}
#
# Tailscale state is intentionally skipped — re-auth with
# `sudo tailscale up --qr` on the new VM is simpler and more reliable
# than transplanting tailscaled.state across machine identities.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${ZOOM_VM_HOST:-zoom-recorder-aws}"
# Default: store under data/ next to this script. Directory is gitignored
# (it contains rclone tokens + VNC passwords — never commit).
OUT="${1:-$SCRIPT_DIR/data/zoom-recorder-vm-state-$(date +%Y%m%d-%H%M%S).tar.gz}"

# Resolve to absolute path
OUT="$(realpath -m "$OUT")"
mkdir -p "$(dirname "$OUT")"

echo "Backing up state from $HOST → $OUT"

# Use --files-from with a manifest so missing paths don't abort the whole tar.
# Stream over ssh — no remote tmp file needed.
INCLUDE_ZOOM="${ZOOM_BACKUP_INCLUDE_ZOOM:-}"

ssh -o BatchMode=yes "$HOST" "
set -e
cd \$HOME

# Manifest. Paths that don't exist are silently skipped.
files=()
[[ -d .config/rclone ]]           && files+=(.config/rclone)
[[ -f .config/tigervnc/passwd ]]  && files+=(.config/tigervnc/passwd)
[[ -f .config/tigervnc/.passwd-plain ]] && files+=(.config/tigervnc/.passwd-plain)
[[ -d .config/environment.d ]]    && files+=(.config/environment.d)
[[ -n '$INCLUDE_ZOOM' && -d .zoom ]] && files+=(.zoom)

# Upload markers (~1 KB total)
while IFS= read -r f; do
  files+=(\"\$f\")
done < <(find recordings -maxdepth 1 -name '*.uploaded' 2>/dev/null)

if [[ \${#files[@]} -eq 0 ]]; then
  echo 'nothing to back up' >&2
  exit 1
fi

tar czf - \"\${files[@]}\" 2>/dev/null
" > "$OUT"

SIZE=$(du -h "$OUT" | cut -f1)
total=$(tar tzf "$OUT" | wc -l)
echo
echo "Backup complete: $OUT ($SIZE, $total entries)"
echo
echo "Contents (first 30):"
{ tar tzf "$OUT" | head -30; } || true
echo
echo "Next steps:"
echo "  1. Verify the backup is what you expect."
echo "  2. (optional) Sanity-check rclone in tar:"
echo "       tar xzOf $OUT .config/rclone/rclone.conf | head -5"
echo "  3. Tear down AWS:"
echo "       see the 'Save state and tear down AWS' section in README.md"
