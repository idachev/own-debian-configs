#!/bin/bash
# gdrive-repo-lib.sh — shared helpers for gdrive-repo-push.sh / -pull.sh / -prune.sh.
#
# A project opts in by committing a `.gdrive-repo.conf` at its root:
#
#   GDRIVE_REMOTE=gdrive-investments          # name from `rclone config`
#   GDRIVE_ROOT=investments-sources           # Drive folder that mirrors the repo root
#   GDRIVE_EXCLUDE_FILE=.gdrive-repo-exclude.txt   # rclone exclude list, relative to root; push applies it
#                                                    # directly, pull/prune fold it into their media filter
#   GDRIVE_MEDIA_EXTENSIONS="mp4 m4a mp3"    # what pull/prune/--list treat as "media"
#   GDRIVE_GIT_BUNDLE=1                       # push also uploads a `git bundle --all` of the repo
#   GDRIVE_SYNC_NON_MEDIA=1                   # push mirrors local deletions of NON-media files to Drive
#                                             # (previewed + confirmed); media is copy-only, never deleted
#
# Every script walks up from $PWD to find that file, so it works from any
# subdirectory. Paths on the command line are relative to the repo root and
# map 1:1 onto `<remote>:<root>/<path>` — no sidecars, no index.
#
# Exit-code contract shared by all three scripts:
#   0 = everything selected was handled
#   1 = at least one item failed or was refused
#   2 = precondition missing (no conf, no rclone, bad argument)
#
# Must stay bash 3.2 compatible (stock macOS): no mapfile, no ${var,,},
# no associative arrays, empty arrays expanded as ${arr[@]+"${arr[@]}"}.

GDRIVE_CONF_NAME=".gdrive-repo.conf"

gdrive_die() {
  >&2 echo "error: $*"
  exit 2
}

gdrive_require_rclone() {
  command -v rclone >/dev/null 2>&1 \
    || gdrive_die "rclone not on PATH — install rclone and run 'rclone config' first"
}

# Sets GDRIVE_REPO_ROOT to the nearest ancestor of $PWD holding $GDRIVE_CONF_NAME.
gdrive_find_root() {
  local dir="$PWD"
  while :; do
    if [[ -f "${dir}/${GDRIVE_CONF_NAME}" ]]; then
      GDRIVE_REPO_ROOT="${dir}"
      return 0
    fi
    [[ "${dir}" == "/" ]] && break
    dir="$(command dirname "${dir}")"
  done
  gdrive_die "no ${GDRIVE_CONF_NAME} found in $PWD or any parent — this tree is not set up for gdrive-repo sync"
}

# Sources the conf and validates the required keys. Leaves the shell in
# GDRIVE_REPO_ROOT so relative paths resolve against it.
gdrive_load_conf() {
  gdrive_find_root
  GDRIVE_REMOTE="" GDRIVE_ROOT="" GDRIVE_EXCLUDE_FILE="" GDRIVE_MEDIA_EXTENSIONS="" GDRIVE_GIT_BUNDLE="" GDRIVE_SYNC_NON_MEDIA=""
  # shellcheck disable=SC1090
  source "${GDRIVE_REPO_ROOT}/${GDRIVE_CONF_NAME}"
  [[ -n "${GDRIVE_REMOTE}" ]] || gdrive_die "${GDRIVE_CONF_NAME}: GDRIVE_REMOTE is not set"
  [[ -n "${GDRIVE_ROOT}" ]]   || gdrive_die "${GDRIVE_CONF_NAME}: GDRIVE_ROOT is not set"
  GDRIVE_ROOT="${GDRIVE_ROOT%/}"
  : "${GDRIVE_MEDIA_EXTENSIONS:=mp4}"
  GDRIVE_DEST="${GDRIVE_REMOTE}:${GDRIVE_ROOT}"
  cd "${GDRIVE_REPO_ROOT}" || gdrive_die "cannot cd to ${GDRIVE_REPO_ROOT}"
}

# Same request-rate cap everywhere: one rclone process is a token bucket, so
# this smooths a long listing; it does not coordinate separate processes.
GDRIVE_RCLONE_COMMON=(--tpslimit 10)

# Scratch dir for generated filter files, removed when the script exits.
GDRIVE_TMPDIR="$(command mktemp -d)"
trap 'command rm -rf "${GDRIVE_TMPDIR}"' EXIT

# Dies unless the conf's exclude file (if any) exists. Callers then use
# "${GDRIVE_REPO_ROOT}/${GDRIVE_EXCLUDE_FILE}".
gdrive_check_exclude_file() {
  [[ -z "${GDRIVE_EXCLUDE_FILE}" || -f "${GDRIVE_REPO_ROOT}/${GDRIVE_EXCLUDE_FILE}" ]] \
    || gdrive_die "GDRIVE_EXCLUDE_FILE=${GDRIVE_EXCLUDE_FILE} not found under ${GDRIVE_REPO_ROOT}"
}

# `--exclude-from <file>` when the conf names one. Used by push, which has
# no include rules, so plain excludes are safe.
gdrive_exclude_flags() {
  GDRIVE_EXCLUDE_FLAGS=()
  gdrive_check_exclude_file
  [[ -n "${GDRIVE_EXCLUDE_FILE}" ]] || return 0
  GDRIVE_EXCLUDE_FLAGS=(--exclude-from "${GDRIVE_REPO_ROOT}/${GDRIVE_EXCLUDE_FILE}")
}

# Appends the conf's exclude list to $1 as `- pattern` rules (comments and
# blank lines dropped, surrounding whitespace trimmed). The single place the
# exclude file is turned into filter rules, so media and non-media filters
# cannot disagree about it.
gdrive_exclude_rules() {
  gdrive_check_exclude_file
  [[ -n "${GDRIVE_EXCLUDE_FILE}" ]] || return 0
  command sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' -e 's/^/- /' \
    "${GDRIVE_REPO_ROOT}/${GDRIVE_EXCLUDE_FILE}" >> "$1"
}

# `--filter-from <generated file> --ignore-case` selecting media only: the
# push exclude list first, then `+ *.ext` per media extension, then `- *`.
# rclone applies filter rules in order, first match wins, and it does NOT
# define the order of mixed --include/--exclude flags, so one ordered filter
# file is the only reliable way to combine the two. --ignore-case makes
# `.MP4` from a camera count as media too.
gdrive_media_filter_flags() {
  local f="${GDRIVE_TMPDIR}/media.filter" ext
  : > "${f}"
  gdrive_exclude_rules "${f}"
  for ext in ${GDRIVE_MEDIA_EXTENSIONS}; do
    echo "+ *.${ext}" >> "${f}"
  done
  echo "- *" >> "${f}"
  GDRIVE_MEDIA_FILTER_FLAGS=(--filter-from "${f}" --ignore-case)
}

# Normalizes a user path: strips ./ and trailing /, refuses absolute or
# parent-escaping paths. Prints the clean path.
gdrive_clean_rel_path() {
  local p="$1"
  p="${p#./}"
  p="${p%/}"
  [[ -n "${p}" ]]           || gdrive_die "empty path"
  [[ "${p}" != /* ]]        || gdrive_die "path must be relative to the repo root: ${1}"
  case "/${p}/" in
    */../*) gdrive_die "path must not contain '..': ${1}" ;;
  esac
  printf '%s\n' "${p}"
}

# Byte size of a local file, portable across GNU and BSD stat.
gdrive_local_size() {
  command wc -c < "$1" | command tr -d ' '
}

# `rclone lsjson --stat` for one remote path. Sets GDRIVE_STAT_KIND to
# dir | file | absent and GDRIVE_STAT_SIZE (bytes, for a file) and returns 0.
# Any other outcome is a FAILED call (auth, quota, network): returns rclone's
# exit code and callers must not read "absent" out of it. rclone answers
# exit 3 for a missing path, the only code that means absence.
gdrive_remote_stat() {
  local rel="$1" out rc=0
  GDRIVE_STAT_KIND="" GDRIVE_STAT_SIZE=""
  out="$(rclone lsjson --stat --no-modtime "${GDRIVE_DEST}/${rel}" \
    ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} 2>/dev/null)" || rc=$?
  if [[ ${rc} -eq 3 ]]; then
    GDRIVE_STAT_KIND=absent
    return 0
  fi
  [[ ${rc} -eq 0 ]] || return "${rc}"
  # rclone pretty-prints `lsjson --stat` ("IsDir": true), so tolerate spaces.
  if printf '%s\n' "${out}" | command grep -q '"IsDir": *true'; then
    GDRIVE_STAT_KIND=dir
    return 0
  fi
  GDRIVE_STAT_KIND=file
  GDRIVE_STAT_SIZE="$(printf '%s\n' "${out}" \
    | command sed -n 's/.*"Size": *\([0-9-]*\).*/\1/p' | command head -n 1)"
}

# Writes the local media files under a repo-relative path (a file or a
# directory) to $2, one repo-relative path per line, sorted. A directory is
# walked with `rclone lsf` under the same media filter pull uses, so the push
# exclude list applies (a transcription cache is not "local-only media").
# Returns rclone's exit code; the caller must check it — an empty file with
# a non-zero code is a failed walk, not an empty tree.
gdrive_local_media_list() {
  local rel="$1" out="$2" rc=0
  : > "${out}"
  if [[ -f "${rel}" ]]; then
    printf '%s\n' "${rel}" > "${out}"
    return 0
  fi
  [[ -d "${rel}" ]] || return 0
  local prefix=""
  [[ "${rel}" == "." ]] || prefix="${rel}/"
  rclone lsf -R --files-only "${rel}" "${GDRIVE_MEDIA_FILTER_FLAGS[@]}" 2>/dev/null \
    | command sed "s|^|${prefix}|" | command sort > "${out}" || rc=$?
  return "${rc}"
}

# True when git tracks the file (so it is not a Drive-only asset).
gdrive_git_tracked() {
  git ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}
