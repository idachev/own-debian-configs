#!/bin/bash
# gdrive-repo-push.sh — upload the current project to its Drive mirror.
#
# Reads `.gdrive-repo.conf` from the repo root (see gdrive-repo-lib.sh).
#
# Usage:
#   gdrive-repo-push.sh                    # rclone copy: upload new/changed files, never delete
#   gdrive-repo-push.sh --dry-run          # preview without uploading
#   gdrive-repo-push.sh --transfers 16     # extra rclone flags are passed through
#   GDRIVE_MAX_DELETE=5 gdrive-repo-push.sh    # rclone sync, at most 5 deletes on Drive
#   GDRIVE_MAX_DELETE=-1 gdrive-repo-push.sh   # rclone sync, unlimited deletes
#
# Upload-only by default. `rclone copy` never deletes anything on Drive, and
# large media files are gitignored — Drive is their ONLY off-machine copy. A
# run from a PARTIAL checkout (a fresh clone that pulled a few files with
# gdrive-repo-pull.sh, or a machine after gdrive-repo-prune.sh) would look to
# `rclone sync` like "the user deleted everything". `copy` cannot make that
# mistake.
#
# Deleting from Drive (a renamed directory, a retired file) is opt-in through
# GDRIVE_MAX_DELETE. The flag is placed AFTER "$@" so a passed-through flag
# cannot raise the cap by accident. rclone refuses deletes above the cap, logs
# "--max-delete threshold reached" per refusal, and exits 7. NOT
# `--max-delete-size`: measured on rclone v1.74 it did not fire at all.
#
# Logs to <repo>/tmp/claude-logs/gdrive-push-<ts>.log. Resume is automatic —
# files already on Drive with matching size + modtime are skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gdrive-repo-lib.sh
source "${SCRIPT_DIR}/gdrive-repo-lib.sh"

gdrive_require_rclone
gdrive_load_conf

EXCLUDE_FLAGS=()
if [[ -n "${GDRIVE_EXCLUDE_FILE}" ]]; then
  [[ -f "${GDRIVE_EXCLUDE_FILE}" ]] \
    || gdrive_die "GDRIVE_EXCLUDE_FILE=${GDRIVE_EXCLUDE_FILE} not found under ${GDRIVE_REPO_ROOT}"
  EXCLUDE_FLAGS=(--exclude-from "${GDRIVE_EXCLUDE_FILE}")
fi

LOG_DIR="${GDRIVE_REPO_ROOT}/tmp/claude-logs"
command mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/gdrive-push-$(command date +%Y%m%d-%H%M%S).log"

MAX_DELETE="${GDRIVE_MAX_DELETE:-}"
if [[ -n "${MAX_DELETE}" ]]; then
  MODE=sync
  GUARD=(--max-delete "${MAX_DELETE}")
  echo "mode: sync (deletes allowed: ${MAX_DELETE})"
else
  MODE=copy
  GUARD=()
  echo "mode: copy (never deletes on Drive; set GDRIVE_MAX_DELETE=<n> to sync)"
fi

echo "${MODE}ing ${GDRIVE_REPO_ROOT} -> ${GDRIVE_DEST}/"
echo "log: ${LOG}"

rc=0
rclone "${MODE}" . "${GDRIVE_DEST}/" \
  ${EXCLUDE_FLAGS[@]+"${EXCLUDE_FLAGS[@]}"} \
  --drive-chunk-size 128M \
  --transfers 8 --checkers 8 \
  ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
  --retries 5 --retries-sleep 30s \
  --low-level-retries 10 \
  --stats=60s --stats-one-line \
  --log-file "${LOG}" \
  --log-level INFO \
  "$@" \
  ${GUARD[@]+"${GUARD[@]}"} || rc=$?

if [[ "${rc}" -ne 0 ]]; then
  echo >&2
  echo "rclone ${MODE} exited ${rc} — see ${LOG}" >&2
  if [[ "${MODE}" = sync ]] && command grep -q -- "--max-delete threshold reached" "${LOG}"; then
    echo "the log contains '--max-delete threshold reached': deletes above ${MAX_DELETE} were refused. Check the log for other errors too." >&2
  fi
fi

exit "${rc}"
