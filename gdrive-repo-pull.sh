#!/bin/bash
# gdrive-repo-pull.sh — download media files from the project's Drive mirror.
#
# Reads `.gdrive-repo.conf` from the repo root (see gdrive-repo-lib.sh).
# Paths are relative to the repo root and map 1:1 onto the Drive mirror.
# Only files with a GDRIVE_MEDIA_EXTENSIONS extension, and outside the push
# exclude list, are pulled from a directory, so git-tracked sidecars (.srt,
# .json, ...) are never overwritten by a stale Drive copy. Naming a single
# file pulls it whatever its extension.
#
# Usage:
#   gdrive-repo-pull.sh sources/lectures/01-key-metrics-analysis-20260518   # one directory
#   gdrive-repo-pull.sh media/202605/20260527/20260527-1-izhvyrli/20260527-1-izhvyrli.mp4
#   gdrive-repo-pull.sh --dry-run media/202605
#   gdrive-repo-pull.sh --list [dir]       # what is local, what is only on Drive (one dir, one listing)
#
# A file already present with the same byte size as on Drive is skipped
# (rclone's own size+modtime check). Exit codes: 0 all handled, 1 at least
# one path failed, 2 bad invocation / no conf / no rclone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gdrive-repo-lib.sh
source "${SCRIPT_DIR}/gdrive-repo-lib.sh"

usage() {
  command sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | command sed '$d' | command sed 's/^# \{0,1\}//'
  exit 2
}

DRY_RUN=0
LIST=0
PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --list)    LIST=1 ;;
    -h|--help) usage ;;
    --*)       gdrive_die "unknown flag: $1" ;;
    *)         PATHS+=("$(gdrive_clean_rel_path "$1")") ;;
  esac
  shift
done

gdrive_require_rclone
gdrive_load_conf
gdrive_media_filter_flags

# --list: one recursive listing of the remote (media only), compared against
# a local listing made with the same filter (media extensions AND the push
# exclude list), so caches push never uploads do not show up as local-only.
# States: present (same size), differs (size mismatch), drive-only, local-only.
if [[ ${LIST} -eq 1 ]]; then
  [[ ${#PATHS[@]} -le 1 ]] || gdrive_die "--list takes at most one directory, got ${#PATHS[@]} paths"
  SCOPE=""
  [[ ${#PATHS[@]} -gt 0 ]] && SCOPE="${PATHS[0]}"
  PREFIX="${SCOPE:+${SCOPE}/}"
  rc=0
  REMOTE_LIST="$(rclone lsf -R --files-only --format ps --separator '|' \
    "${GDRIVE_DEST}${SCOPE:+/${SCOPE}}" \
    "${GDRIVE_MEDIA_FILTER_FLAGS[@]}" \
    ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} 2>/dev/null)" || rc=$?
  if [[ ${rc} -eq 3 ]]; then
    gdrive_die "no such directory on Drive: ${GDRIVE_DEST}/${SCOPE} (paths are relative to ${GDRIVE_REPO_ROOT})"
  elif [[ ${rc} -ne 0 ]]; then
    gdrive_die "rclone lsf exited ${rc} for ${GDRIVE_DEST}/${SCOPE} — auth, quota or network"
  fi
  TMP_REMOTE="${GDRIVE_TMPDIR}/remote.list"        # repo-relative path|size
  TMP_REMOTE_PATHS="${GDRIVE_TMPDIR}/remote.paths"
  TMP_LOCAL="${GDRIVE_TMPDIR}/local.paths"
  printf '%s\n' "${REMOTE_LIST}" | command sed -e '/^$/d' -e "s|^|${PREFIX}|" | command sort > "${TMP_REMOTE}"
  command cut -d'|' -f1 "${TMP_REMOTE}" > "${TMP_REMOTE_PATHS}"

  rc=0
  gdrive_local_media_list "${SCOPE:-.}" "${TMP_LOCAL}" || rc=$?
  [[ ${rc} -eq 0 ]] || gdrive_die "local listing of ${SCOPE:-.} failed (rclone lsf exit ${rc}) — refusing to report it as fully synced"

  n_present=0 n_differs=0 n_drive=0 n_local=0
  while IFS='|' read -r rpath rsize; do
    [[ -n "${rpath}" ]] || continue
    if [[ -f "${rpath}" ]]; then
      if [[ "$(gdrive_local_size "${rpath}")" == "${rsize}" ]]; then
        echo "present     ${rpath}"; n_present=$((n_present + 1))
      else
        echo "differs     ${rpath}"; n_differs=$((n_differs + 1))
      fi
    else
      echo "drive-only  ${rpath}"; n_drive=$((n_drive + 1))
    fi
  done < "${TMP_REMOTE}"

  while IFS= read -r lpath; do
    [[ -n "${lpath}" ]] || continue
    echo "local-only  ${lpath}"; n_local=$((n_local + 1))
  done < <(command comm -13 "${TMP_REMOTE_PATHS}" "${TMP_LOCAL}")

  echo "summary: ${n_present} present, ${n_differs} differs, ${n_drive} drive-only, ${n_local} local-only"
  exit 0
fi

[[ ${#PATHS[@]} -gt 0 ]] || usage

DRY=()
[[ ${DRY_RUN} -eq 1 ]] && DRY=(--dry-run)

failed=0
for rel in "${PATHS[@]}"; do
  rc=0
  gdrive_remote_stat "${rel}" || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    # A failed stat says nothing about the path. Falling through to a copy
    # here once turned a directory pull into an unfiltered tree copy.
    >&2 echo "failed: ${rel} — Drive check failed (rclone exit ${rc}: auth/quota/network)"; failed=1; continue
  fi
  case "${GDRIVE_STAT_KIND}" in
    absent)
      >&2 echo "failed: ${rel} — not on Drive"; failed=1 ;;
    dir)
      echo "pull dir  ${rel}/"
      rclone copy "${GDRIVE_DEST}/${rel}" "${rel}" \
        "${GDRIVE_MEDIA_FILTER_FLAGS[@]}" \
        ${DRY[@]+"${DRY[@]}"} \
        ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
        --transfers 4 --drive-chunk-size 128M --progress \
        || { >&2 echo "failed: ${rel}"; failed=1; } ;;
    file)
      echo "pull file ${rel}"
      rclone copyto "${GDRIVE_DEST}/${rel}" "${rel}" \
        ${DRY[@]+"${DRY[@]}"} \
        ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
        --drive-chunk-size 128M --progress \
        || { >&2 echo "failed: ${rel}"; failed=1; } ;;
  esac
done

exit "${failed}"
