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
# Git history backup: with GDRIVE_GIT_BUNDLE=1 in the conf, the push first
# writes `git bundle create --all` (every branch and tag, one consistent
# file) and uploads it to <root>/.git-backup/<repo-name>.bundle, compared by
# checksum so an unchanged history costs one hash lookup. The bundle is
# packed with pack.threads=1: multi-threaded packing is not byte-stable, so
# without it every push re-uploaded the whole file. `.git-backup/` has no
# local counterpart, so the tree copy below excludes it explicitly — or a
# sync-mode push would delete the bundle it just uploaded. Restore with
# `git clone <name>.bundle <dir>`. This replaces mirroring `.git/**`, which
# is thousands of small files, churns on every gc, and can be copied
# mid-write.
#
# Logs to <repo>/tmp/claude-logs/gdrive-push-<ts>.log. Resume is automatic —
# files already on Drive with matching size + modtime are skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gdrive-repo-lib.sh
source "${SCRIPT_DIR}/gdrive-repo-lib.sh"

gdrive_require_rclone
gdrive_load_conf

gdrive_exclude_flags

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

bundle_rc=0
if [[ "${GDRIVE_GIT_BUNDLE}" == "1" ]]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BUNDLE_NAME="$(command basename "${GDRIVE_REPO_ROOT}").bundle"
    BUNDLE="${GDRIVE_TMPDIR}/${BUNDLE_NAME}"
    BUNDLE_DEST="${GDRIVE_DEST}/.git-backup/${BUNDLE_NAME}"
    echo "git bundle: ${BUNDLE_DEST}"
    if git -c pack.threads=1 bundle create "${BUNDLE}" --all >>"${LOG}" 2>&1; then
      # "$@" is passed through here too, so `--dry-run` / `-n` mean the same
      # for the bundle upload as for the tree copy.
      rclone copyto "${BUNDLE}" "${BUNDLE_DEST}" \
        --checksum --drive-chunk-size 128M \
        ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
        --log-file "${LOG}" --log-level INFO \
        "$@" || bundle_rc=$?
      [[ ${bundle_rc} -eq 0 ]] || >&2 echo "git bundle upload failed (rclone exit ${bundle_rc}) — continuing with the tree"
    else
      bundle_rc=1
      >&2 echo "git bundle create failed — see ${LOG}; continuing with the tree"
    fi
  else
    >&2 echo "GDRIVE_GIT_BUNDLE=1 but ${GDRIVE_REPO_ROOT} is not a git repository — skipping the bundle"
  fi
fi

rc=0
rclone "${MODE}" . "${GDRIVE_DEST}/" \
  ${GDRIVE_EXCLUDE_FLAGS[@]+"${GDRIVE_EXCLUDE_FLAGS[@]}"} \
  --exclude '.git-backup/**' \
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

[[ ${rc} -ne 0 ]] || rc=${bundle_rc}
exit "${rc}"
