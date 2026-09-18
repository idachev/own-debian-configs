#!/bin/bash
# gdrive-repo-push.sh — upload the current project to its Drive mirror.
#
# Reads `.gdrive-repo.conf` from the repo root (see gdrive-repo-lib.sh).
#
# Usage:
#   gdrive-repo-push.sh --dry-run          # preview: uploads, and the non-media files that would be deleted on Drive
#   gdrive-repo-push.sh                    # push; on a terminal, asks before deleting the previewed files
#   gdrive-repo-push.sh --yes              # push; deletes the list a previous --dry-run showed, if it is unchanged
#   gdrive-repo-push.sh --transfers 16     # other rclone flags are passed through (see "Flags" below)
#
# Two modes, chosen by the conf:
#
# GDRIVE_SYNC_NON_MEDIA=1 — the local tree is the source of truth.
#   1. non-media: `rclone check` lists every file on Drive that is not a
#      media file, not under .git-backup/, and no longer exists locally.
#      The list is printed. Then `rclone copy` uploads new/changed non-media
#      files. Then, ONLY IF CONFIRMED, `rclone delete --files-from-raw`
#      removes exactly the listed files — never a recomputed set, never a
#      count-capped "some of them". Confirmation is the y/N prompt on a
#      terminal, or --yes when the list equals the one the last --dry-run
#      wrote to tmp/claude-logs/gdrive-push-pending-deletes.list. No
#      terminal and no --yes, or a --yes whose list changed: the deletions
#      are SKIPPED, everything else still uploads, exit 1 says so.
#   2. media: `rclone copy` of files with a GDRIVE_MEDIA_EXTENSIONS extension.
#      Never deletes — a media file pruned locally to free disk stays on Drive.
#   3. git bundle (below), upload only. Runs after the deletion decision so a
#      refused run has changed nothing but uploads.
#   Drive-side deletions are never mirrored back: a file removed on Drive is
#   simply uploaded again on the next push. GDRIVE_MAX_DELETE is refused in
#   this mode (exit 2) rather than silently ignored.
#
# Default (no GDRIVE_SYNC_NON_MEDIA) — one `rclone copy` of the whole tree,
# never deletes. GDRIVE_MAX_DELETE=<n> switches that single pass to
# `rclone sync --max-delete n` for a deliberate one-off cleanup.
#
# Flags: --yes/-y and --dry-run/-n are consumed here (--dry-run is also passed
# on to rclone). Flags that would change WHAT is selected, deleted or logged
# are refused with exit 2, because the safety of pass 1 depends on them:
# --include*, --exclude*, --filter*, --files-from*, --delete-*, --max-delete*,
# --log-file, --log-level, --use-json-log, -v/-q and any short-flag cluster.
#
# Git history backup: with GDRIVE_GIT_BUNDLE=1 in the conf, the push writes
# `git bundle create --all` (every branch and tag, one consistent file) and
# uploads it to <root>/.git-backup/<repo-name>.bundle, compared by checksum
# so an unchanged history costs one hash lookup. The bundle is packed with
# pack.threads=1: multi-threaded packing is not byte-stable, so without it
# every push re-uploaded the whole file. `.git-backup/` has no local
# counterpart, so every tree pass excludes it. Restore with
# `git clone <name>.bundle <dir>`.
#
# Logs to <repo>/tmp/claude-logs/gdrive-push-<ts>.log. Resume is automatic —
# files already on Drive with matching size + modtime are skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gdrive-repo-lib.sh
source "${SCRIPT_DIR}/gdrive-repo-lib.sh"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
ASSUME_YES=0
USER_DRY=0
PASS=()
for a in "$@"; do
  case "$a" in
    --yes|-y)                 ASSUME_YES=1 ;;
    --dry-run|--dry-run=true|-n) USER_DRY=1; PASS+=(--dry-run) ;;
    --include*|--exclude*|--filter*|--files-from*|--delete-*|--max-delete*|\
    --log-file*|--log-level*|--use-json-log|-v|-vv|-q)
      gdrive_die "flag $a is not allowed: it would change what push selects, deletes or logs (see the header)" ;;
    -[A-Za-z][A-Za-z]*)
      gdrive_die "short-flag cluster $a is not allowed — spell flags out (--dry-run, --yes, --transfers 16)" ;;
    *)                        PASS+=("$a") ;;
  esac
done

gdrive_require_rclone
gdrive_load_conf

LOG_DIR="${GDRIVE_REPO_ROOT}/tmp/claude-logs"
command mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/gdrive-push-$(command date +%Y%m%d-%H%M%S).log"
PENDING="${LOG_DIR}/gdrive-push-pending-deletes.list"

RCLONE_BASE=(
  --drive-chunk-size 128M
  --transfers 8 --checkers 8
  ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"}
  --retries 5 --retries-sleep 30s
  --low-level-retries 10
  "--stats=60s" --stats-one-line
  --log-file "${LOG}" --log-level INFO
)

echo "repo: ${GDRIVE_REPO_ROOT} -> ${GDRIVE_DEST}/"
echo "log:  ${LOG}"

rc=0
note_rc() { # keep the first non-zero code
  [[ ${rc} -ne 0 ]] || rc=$1
}

# ---------------------------------------------------------------------------
# Git bundle — called after the deletion decision in sync mode
# ---------------------------------------------------------------------------
push_bundle() {
  [[ "${GDRIVE_GIT_BUNDLE}" == "1" ]] || return 0
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    >&2 echo "GDRIVE_GIT_BUNDLE=1 but ${GDRIVE_REPO_ROOT} is not a git repository — skipping the bundle"
    return 0
  fi
  local name bundle dest brc=0
  name="$(command basename "${GDRIVE_REPO_ROOT}").bundle"
  bundle="${GDRIVE_TMPDIR}/${name}"
  dest="${GDRIVE_DEST}/.git-backup/${name}"
  echo "git bundle: ${dest}"
  if ! git -c pack.threads=1 bundle create "${bundle}" --all >>"${LOG}" 2>&1; then
    >&2 echo "git bundle create failed — see ${LOG}"
    note_rc 1
    return 0
  fi
  rclone copyto "${bundle}" "${dest}" --checksum "${RCLONE_BASE[@]}" \
    ${PASS[@]+"${PASS[@]}"} || brc=$?
  if [[ ${brc} -ne 0 ]]; then
    >&2 echo "git bundle upload failed (rclone exit ${brc}) — see ${LOG}"
    note_rc "${brc}"
  fi
}

if [[ "${GDRIVE_SYNC_NON_MEDIA}" == "1" ]]; then
  [[ -z "${GDRIVE_MAX_DELETE:-}" ]] \
    || gdrive_die "GDRIVE_MAX_DELETE has no effect with GDRIVE_SYNC_NON_MEDIA=1 — deletions are the previewed list, confirmed with --yes"
  gdrive_non_media_filter_flags
  gdrive_media_filter_flags

  # -------------------------------------------------------------------------
  # Pass 1a — what would be deleted: non-media files on Drive, absent locally
  # -------------------------------------------------------------------------
  echo "pass 1/3: non-media (upload; delete on Drive what was deleted locally, after confirmation)"
  DELETES="${GDRIVE_TMPDIR}/deletes.list"
  RAW="${GDRIVE_TMPDIR}/deletes.raw"
  crc=0
  # `check` exits 0 when both sides match and 1 when they differ; both are
  # answers. Anything else is a failed call and the push stops here, before
  # any upload, so a half-listed Drive is never acted on.
  rclone check . "${GDRIVE_DEST}/" --size-only --missing-on-src "${RAW}" \
    "${GDRIVE_NON_MEDIA_FILTER_FLAGS[@]}" \
    ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
    --log-file "${LOG}" --log-level ERROR || crc=$?
  if [[ ${crc} -ne 0 && ${crc} -ne 1 ]]; then
    >&2 echo "rclone check exited ${crc} — cannot tell what is on Drive; nothing changed. See ${LOG}"
    exit "${crc}"
  fi
  command sort -u "${RAW}" | command sed '/^$/d' > "${DELETES}"
  n_del="$(command grep -c . "${DELETES}" || true)"

  DO_DELETE=0
  deletes_skipped=0
  if [[ "${n_del}" -gt 0 ]]; then
    echo "${n_del} non-media file(s) exist on Drive but not locally and would be DELETED on Drive:"
    command sed 's/^/  - /' "${DELETES}"
    if [[ ${USER_DRY} -eq 1 ]]; then
      command cp "${DELETES}" "${PENDING}"
      echo "(dry run — this list is saved for a following --yes: ${PENDING})"
    elif [[ ${ASSUME_YES} -eq 1 ]]; then
      if [[ -f "${PENDING}" ]] && command cmp -s "${DELETES}" "${PENDING}"; then
        DO_DELETE=1
      else
        deletes_skipped=1
        >&2 echo "--yes refused: the list differs from the last --dry-run (or none was run). Deletions SKIPPED; uploads continue. Re-run --dry-run, review, then --yes."
      fi
    elif [[ -t 0 ]]; then
      printf 'Delete these %s file(s) on Drive? [y/N] ' "${n_del}" > /dev/tty
      read -r answer < /dev/tty
      if [[ "${answer}" == y || "${answer}" == Y ]]; then
        DO_DELETE=1
      else
        deletes_skipped=1
        echo "deletions SKIPPED; uploads continue"
      fi
    else
      deletes_skipped=1
      >&2 echo "no terminal to confirm on. Deletions SKIPPED; uploads continue. Run --dry-run, review the list, then --yes."
    fi
  else
    echo "no Drive-side deletions pending"
    [[ ${USER_DRY} -eq 1 ]] && : > "${PENDING}"
  fi

  # -------------------------------------------------------------------------
  # Pass 1b — upload non-media; 1c — delete exactly the confirmed list
  # -------------------------------------------------------------------------
  urc=0
  rclone copy . "${GDRIVE_DEST}/" "${GDRIVE_NON_MEDIA_FILTER_FLAGS[@]}" \
    "${RCLONE_BASE[@]}" ${PASS[@]+"${PASS[@]}"} || urc=$?
  [[ ${urc} -eq 0 ]] || { >&2 echo "non-media upload exited ${urc} — see ${LOG}"; note_rc "${urc}"; }

  if [[ ${DO_DELETE} -eq 1 ]]; then
    drc=0
    rclone delete "${GDRIVE_DEST}/" --files-from-raw "${DELETES}" \
      "${RCLONE_BASE[@]}" ${PASS[@]+"${PASS[@]}"} || drc=$?
    if [[ ${drc} -eq 0 ]]; then
      echo "deleted ${n_del} file(s) on Drive"
      command rm -f "${PENDING}"
    else
      >&2 echo "rclone delete exited ${drc} — see ${LOG}"; note_rc "${drc}"
    fi
  fi

  # -------------------------------------------------------------------------
  # Pass 2 — media: copy only, never deletes
  # -------------------------------------------------------------------------
  echo "pass 2/3: media copy (never deletes on Drive)"
  mrc=0
  rclone copy . "${GDRIVE_DEST}/" "${GDRIVE_MEDIA_FILTER_FLAGS[@]}" \
    "${RCLONE_BASE[@]}" ${PASS[@]+"${PASS[@]}"} || mrc=$?
  [[ ${mrc} -eq 0 ]] || { >&2 echo "media copy exited ${mrc} — see ${LOG}"; note_rc "${mrc}"; }

  echo "pass 3/3: git bundle"
  push_bundle

  if [[ ${deletes_skipped} -eq 1 ]]; then
    >&2 echo "push finished with the Drive-side deletions SKIPPED (${n_del} file(s) still on Drive)"
    note_rc 1
  fi

else
  # -------------------------------------------------------------------------
  # Legacy single pass — copy, or sync with an explicit cap
  # -------------------------------------------------------------------------
  gdrive_exclude_flags
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
  push_bundle
  lrc=0
  rclone "${MODE}" . "${GDRIVE_DEST}/" \
    ${GDRIVE_EXCLUDE_FLAGS[@]+"${GDRIVE_EXCLUDE_FLAGS[@]}"} \
    --exclude '.git-backup/**' \
    "${RCLONE_BASE[@]}" \
    ${PASS[@]+"${PASS[@]}"} \
    ${GUARD[@]+"${GUARD[@]}"} || lrc=$?
  if [[ ${lrc} -ne 0 ]]; then
    >&2 echo "rclone ${MODE} exited ${lrc} — see ${LOG}"
    if [[ "${MODE}" = sync ]] && command grep -q -- "--max-delete threshold reached" "${LOG}"; then
      >&2 echo "the log contains '--max-delete threshold reached': deletes above ${MAX_DELETE} were refused."
    fi
    note_rc "${lrc}"
  fi
fi

exit "${rc}"
