#!/bin/bash
# gdrive-repo-push.sh — upload the current project to its Drive mirror.
#
# Reads `.gdrive-repo.conf` from the repo root (see gdrive-repo-lib.sh).
#
# Usage:
#   gdrive-repo-push.sh                    # upload; with GDRIVE_SYNC_NON_MEDIA=1 also mirror deletions of non-media
#   gdrive-repo-push.sh --dry-run          # preview everything (uploads and deletions), change nothing
#   gdrive-repo-push.sh --yes              # do not ask before deleting the previewed non-media files
#   gdrive-repo-push.sh --transfers 16     # other flags are passed through to rclone
#
# Two modes, chosen by the conf:
#
# GDRIVE_SYNC_NON_MEDIA=1 — the local tree is the source of truth. Three passes:
#   1. non-media: `rclone sync` over everything that is NOT a media file and
#      not `.git-backup/`. New/changed files go up; files that no longer exist
#      locally are deleted on Drive. The deletions are previewed first with a
#      dry run and listed; the real sync runs only after the user confirms
#      (or with --yes), and is capped with --max-delete at exactly the
#      previewed count. No tty and no --yes = abort with exit 1, nothing deleted.
#   2. media: `rclone copy` of files with a GDRIVE_MEDIA_EXTENSIONS extension.
#      Never deletes — a media file pruned locally to free disk stays on Drive.
#   3. git bundle (see below), upload only.
#   Drive-side deletions are never mirrored back: a file removed on Drive is
#   simply uploaded again on the next push.
#
# Default (no GDRIVE_SYNC_NON_MEDIA) — one `rclone copy` of the whole tree,
# never deletes. GDRIVE_MAX_DELETE=<n> switches that single pass to
# `rclone sync --max-delete n` for a deliberate one-off cleanup.
#
# Git history backup: with GDRIVE_GIT_BUNDLE=1 in the conf, the push first
# writes `git bundle create --all` (every branch and tag, one consistent
# file) and uploads it to <root>/.git-backup/<repo-name>.bundle, compared by
# checksum so an unchanged history costs one hash lookup. The bundle is
# packed with pack.threads=1: multi-threaded packing is not byte-stable, so
# without it every push re-uploaded the whole file. `.git-backup/` has no
# local counterpart, so every tree pass excludes it — or a sync would delete
# the bundle it just uploaded. Restore with `git clone <name>.bundle <dir>`.
#
# Logs to <repo>/tmp/claude-logs/gdrive-push-<ts>.log (the deletion preview
# to gdrive-push-<ts>-preview.log). Resume is automatic — files already on
# Drive with matching size + modtime are skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gdrive-repo-lib.sh
source "${SCRIPT_DIR}/gdrive-repo-lib.sh"

# Own flags are consumed here; everything else is passed through to rclone.
ASSUME_YES=0
USER_DRY=0
PASS=()
for a in "$@"; do
  case "$a" in
    --yes|-y)        ASSUME_YES=1 ;;
    --dry-run|-n)    USER_DRY=1; PASS+=("$a") ;;
    *)               PASS+=("$a") ;;
  esac
done

gdrive_require_rclone
gdrive_load_conf
gdrive_exclude_flags

LOG_DIR="${GDRIVE_REPO_ROOT}/tmp/claude-logs"
command mkdir -p "${LOG_DIR}"
STAMP="$(command date +%Y%m%d-%H%M%S)"
LOG="${LOG_DIR}/gdrive-push-${STAMP}.log"
PREVIEW_LOG="${LOG_DIR}/gdrive-push-${STAMP}-preview.log"

RCLONE_BASE=(
  --drive-chunk-size 128M
  --transfers 8 --checkers 8
  ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"}
  --retries 5 --retries-sleep 30s
  --low-level-retries 10
  --stats=60s --stats-one-line
  --log-level INFO
)

echo "repo: ${GDRIVE_REPO_ROOT} -> ${GDRIVE_DEST}/"
echo "log:  ${LOG}"

# ---------------------------------------------------------------------------
# Pass 0 — git bundle
# ---------------------------------------------------------------------------
bundle_rc=0
if [[ "${GDRIVE_GIT_BUNDLE}" == "1" ]]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BUNDLE_NAME="$(command basename "${GDRIVE_REPO_ROOT}").bundle"
    BUNDLE="${GDRIVE_TMPDIR}/${BUNDLE_NAME}"
    BUNDLE_DEST="${GDRIVE_DEST}/.git-backup/${BUNDLE_NAME}"
    echo "git bundle: ${BUNDLE_DEST}"
    if git -c pack.threads=1 bundle create "${BUNDLE}" --all >>"${LOG}" 2>&1; then
      rclone copyto "${BUNDLE}" "${BUNDLE_DEST}" \
        --checksum --drive-chunk-size 128M \
        ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
        --log-file "${LOG}" --log-level INFO \
        ${PASS[@]+"${PASS[@]}"} || bundle_rc=$?
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

if [[ "${GDRIVE_SYNC_NON_MEDIA}" == "1" ]]; then
  # -------------------------------------------------------------------------
  # Pass 1 — non-media: sync with a previewed, confirmed, capped delete set
  # -------------------------------------------------------------------------
  gdrive_non_media_filter_flags
  gdrive_media_filter_flags

  echo "pass 1/2: non-media sync (local deletions mirrored to Drive after confirmation)"
  : > "${PREVIEW_LOG}"
  prc=0
  rclone sync . "${GDRIVE_DEST}/" \
    "${GDRIVE_NON_MEDIA_FILTER_FLAGS[@]}" \
    "${RCLONE_BASE[@]}" --log-file "${PREVIEW_LOG}" \
    ${PASS[@]+"${PASS[@]}"} --dry-run || prc=$?
  if [[ ${prc} -ne 0 ]]; then
    >&2 echo "preview sync failed (rclone exit ${prc}) — see ${PREVIEW_LOG}; nothing changed on Drive"
    exit "${prc}"
  fi
  # rclone --dry-run logs one "NOTICE: <path>: Skipped delete as --dry-run is set" per file.
  DELETES="${GDRIVE_TMPDIR}/deletes.list"
  command sed -n 's/^.*NOTICE: \(.*\): Skipped delete as --dry-run is set.*$/\1/p' "${PREVIEW_LOG}" \
    | command grep -v '^Google drive root' > "${DELETES}" || true
  n_del="$(command grep -c . "${DELETES}" || true)"

  if [[ "${n_del}" -gt 0 ]]; then
    echo "${n_del} non-media file(s) exist on Drive but not locally and would be DELETED on Drive:"
    command sed 's/^/  - /' "${DELETES}"
  else
    echo "no Drive-side deletions pending"
  fi

  if [[ ${USER_DRY} -eq 1 ]]; then
    echo "(dry run — uploads that would happen are in ${PREVIEW_LOG})"
  else
    if [[ "${n_del}" -gt 0 && ${ASSUME_YES} -ne 1 ]]; then
      if [[ -t 0 ]]; then
        printf 'Delete these %s file(s) on Drive? [y/N] ' "${n_del}"
        read -r answer
        [[ "${answer}" == y || "${answer}" == Y ]] || { echo "aborted — nothing changed on Drive"; exit 1; }
      else
        >&2 echo "no terminal to confirm on; re-run with --yes to delete them, or --dry-run to only preview"
        exit 1
      fi
    fi
    rclone sync . "${GDRIVE_DEST}/" \
      "${GDRIVE_NON_MEDIA_FILTER_FLAGS[@]}" \
      "${RCLONE_BASE[@]}" --log-file "${LOG}" \
      ${PASS[@]+"${PASS[@]}"} \
      --max-delete "${n_del}" || rc=$?
    [[ ${rc} -eq 0 ]] || >&2 echo "non-media sync exited ${rc} — see ${LOG}"
  fi

  # -------------------------------------------------------------------------
  # Pass 2 — media: copy only, never deletes
  # -------------------------------------------------------------------------
  echo "pass 2/2: media copy (never deletes on Drive)"
  crc=0
  rclone copy . "${GDRIVE_DEST}/" \
    "${GDRIVE_MEDIA_FILTER_FLAGS[@]}" \
    "${RCLONE_BASE[@]}" --log-file "${LOG}" \
    ${PASS[@]+"${PASS[@]}"} || crc=$?
  [[ ${crc} -eq 0 ]] || { >&2 echo "media copy exited ${crc} — see ${LOG}"; [[ ${rc} -ne 0 ]] || rc=${crc}; }

else
  # -------------------------------------------------------------------------
  # Legacy single pass — copy, or sync with an explicit cap
  # -------------------------------------------------------------------------
  MAX_DELETE="${GDRIVE_MAX_DELETE:-}"
  if [[ -n "${MAX_DELETE}" ]]; then
    MODE=sync
    GUARD=(--max-delete "${MAX_DELETE}")
    echo "mode: sync (deletes allowed: ${MAX_DELETE})"
  else
    MODE=copy
    GUARD=()
    echo "mode: copy (never deletes on Drive; set GDRIVE_MAX_DELETE=<n> to sync, or GDRIVE_SYNC_NON_MEDIA=1 in the conf)"
  fi
  rclone "${MODE}" . "${GDRIVE_DEST}/" \
    ${GDRIVE_EXCLUDE_FLAGS[@]+"${GDRIVE_EXCLUDE_FLAGS[@]}"} \
    --exclude '.git-backup/**' \
    "${RCLONE_BASE[@]}" --log-file "${LOG}" \
    ${PASS[@]+"${PASS[@]}"} \
    ${GUARD[@]+"${GUARD[@]}"} || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    >&2 echo "rclone ${MODE} exited ${rc} — see ${LOG}"
    if [[ "${MODE}" = sync ]] && command grep -q -- "--max-delete threshold reached" "${LOG}"; then
      >&2 echo "the log contains '--max-delete threshold reached': deletes above ${MAX_DELETE} were refused."
    fi
  fi
fi

[[ ${rc} -ne 0 ]] || rc=${bundle_rc}
exit "${rc}"
