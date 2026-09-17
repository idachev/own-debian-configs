#!/bin/bash
# gdrive-repo-prune.sh — free local disk by deleting media files that Drive holds.
#
# Reads `.gdrive-repo.conf` from the repo root (see gdrive-repo-lib.sh).
# Paths are relative to the repo root. A directory expands to every local
# file with a GDRIVE_MEDIA_EXTENSIONS extension beneath it.
#
# A file is deleted ONLY when `rclone lsjson --stat` confirms a Drive copy of
# the same byte size. Absent on Drive, different size, a failed Drive call,
# or a git-tracked file: refused and reported, never deleted — the local file
# may be the only copy left.
#
# Usage:
#   gdrive-repo-prune.sh sources/kurs-fundmentalen-analiz/11-urok-11
#   gdrive-repo-prune.sh --dry-run media/202604
#
# Exit codes: 0 every file pruned (or already absent), 1 at least one file
# refused or failed, 2 bad invocation / no conf / no rclone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gdrive-repo-lib.sh
source "${SCRIPT_DIR}/gdrive-repo-lib.sh"

usage() {
  command sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | command sed '$d' | command sed 's/^# \{0,1\}//'
  exit 2
}

DRY_RUN=0
PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    --*)       gdrive_die "unknown flag: $1" ;;
    *)         PATHS+=("$(gdrive_clean_rel_path "$1")") ;;
  esac
  shift
done
[[ ${#PATHS[@]} -gt 0 ]] || usage

gdrive_require_rclone
gdrive_load_conf

n_pruned=0 n_refused=0
for rel in "${PATHS[@]}"; do
  if [[ ! -e "${rel}" ]]; then
    echo "absent      ${rel} (nothing local to prune)"
    continue
  fi
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    if gdrive_git_tracked "${f}"; then
      echo "refused     ${f} — tracked by git"; n_refused=$((n_refused + 1)); continue
    fi
    local_size="$(gdrive_local_size "${f}")"
    rc=0
    remote_size="$(gdrive_remote_size "${f}")" || rc=$?
    if [[ ${rc} -eq 3 ]]; then
      echo "refused     ${f} — not on Drive"; n_refused=$((n_refused + 1)); continue
    elif [[ ${rc} -ne 0 ]]; then
      echo "refused     ${f} — Drive check failed (rclone exit ${rc}: auth/quota/network)"; n_refused=$((n_refused + 1)); continue
    fi
    if [[ "${remote_size}" != "${local_size}" ]]; then
      echo "refused     ${f} — Drive has ${remote_size} bytes, local ${local_size}"; n_refused=$((n_refused + 1)); continue
    fi
    if [[ ${DRY_RUN} -eq 1 ]]; then
      echo "would-prune ${f} (${local_size} bytes, verified on Drive)"
    else
      command rm -f -- "${f}"
      echo "pruned      ${f} (${local_size} bytes, verified on Drive)"
    fi
    n_pruned=$((n_pruned + 1))
  done < <(gdrive_local_media_under "${rel}")
done

echo "summary: ${n_pruned} pruned, ${n_refused} refused"
[[ ${n_refused} -eq 0 ]]
