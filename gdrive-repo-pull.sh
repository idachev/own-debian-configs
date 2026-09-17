#!/bin/bash
# gdrive-repo-pull.sh — download media files from the project's Drive mirror.
#
# Reads `.gdrive-repo.conf` from the repo root (see gdrive-repo-lib.sh).
# Paths are relative to the repo root and map 1:1 onto the Drive mirror.
# Only files with a GDRIVE_MEDIA_EXTENSIONS extension are pulled from a
# directory, so git-tracked sidecars (.srt, .json, ...) are never overwritten
# by a stale Drive copy. Naming a single file pulls it whatever its extension.
#
# Usage:
#   gdrive-repo-pull.sh sources/lectures/01-key-metrics-analysis-20260518   # one directory
#   gdrive-repo-pull.sh media/202605/20260527/20260527-1-izhvyrli/20260527-1-izhvyrli.mp4
#   gdrive-repo-pull.sh --dry-run media/202605
#   gdrive-repo-pull.sh --list [dir]       # what is local, what is only on Drive (one listing)
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
# exclude list), so caches push never uploads do not show up as local-only. States:
# present (same size), differs (size mismatch), drive-only, local-only.
if [[ ${LIST} -eq 1 ]]; then
  SCOPE=""
  [[ ${#PATHS[@]} -gt 0 ]] && SCOPE="${PATHS[0]}"
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
  TMP_REMOTE="${GDRIVE_TMPDIR}/remote.list"
  printf '%s\n' "${REMOTE_LIST}" | command sed '/^$/d' > "${TMP_REMOTE}"

  n_present=0 n_differs=0 n_drive=0 n_local=0
  while IFS='|' read -r rpath rsize; do
    [[ -n "${rpath}" ]] || continue
    full="${SCOPE:+${SCOPE}/}${rpath}"
    if [[ -f "${full}" ]]; then
      if [[ "$(gdrive_local_size "${full}")" == "${rsize}" ]]; then
        echo "present     ${full}"; n_present=$((n_present + 1))
      else
        echo "differs     ${full}"; n_differs=$((n_differs + 1))
      fi
    else
      echo "drive-only  ${full}"; n_drive=$((n_drive + 1))
    fi
  done < "${TMP_REMOTE}"

  if [[ -d "${SCOPE:-.}" ]]; then
    while IFS= read -r rel; do
      [[ -n "${rel}" ]] || continue
      if ! command awk -F'|' -v p="${rel}" '$1 == p { found = 1 } END { exit !found }' "${TMP_REMOTE}"; then
        echo "local-only  ${SCOPE:+${SCOPE}/}${rel}"; n_local=$((n_local + 1))
      fi
    done < <(rclone lsf -R --files-only "${SCOPE:-.}" \
      "${GDRIVE_MEDIA_FILTER_FLAGS[@]}" 2>/dev/null | command sort)
  fi

  echo "summary: ${n_present} present, ${n_differs} differs, ${n_drive} drive-only, ${n_local} local-only"
  exit 0
fi

[[ ${#PATHS[@]} -gt 0 ]] || usage

DRY=()
[[ ${DRY_RUN} -eq 1 ]] && DRY=(--dry-run)

failed=0
for rel in "${PATHS[@]}"; do
  if gdrive_remote_is_dir "${rel}"; then
    echo "pull dir  ${rel}/"
    rclone copy "${GDRIVE_DEST}/${rel}" "${rel}" \
      "${GDRIVE_MEDIA_FILTER_FLAGS[@]}" \
      ${DRY[@]+"${DRY[@]}"} \
      ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
      --transfers 4 --drive-chunk-size 128M --progress \
      || { >&2 echo "failed: ${rel}"; failed=1; }
  else
    echo "pull file ${rel}"
    rclone copyto "${GDRIVE_DEST}/${rel}" "${rel}" \
      ${DRY[@]+"${DRY[@]}"} \
      ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} \
      --drive-chunk-size 128M --progress \
      || { >&2 echo "failed: ${rel} (not on Drive, or auth/quota/network)"; failed=1; }
  fi
done

exit "${failed}"
