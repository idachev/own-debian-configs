#!/bin/bash
# gdrive-repo-lib.sh — shared helpers for gdrive-repo-push.sh / -pull.sh / -prune.sh.
#
# A project opts in by committing a `.gdrive-repo.conf` at its root:
#
#   GDRIVE_REMOTE=gdrive-investments          # name from `rclone config`
#   GDRIVE_ROOT=investments-sources           # Drive folder that mirrors the repo root
#   GDRIVE_EXCLUDE_FILE=.gdrive-repo-exclude.txt   # rclone --exclude-from, relative to root (push only)
#   GDRIVE_MEDIA_EXTENSIONS="mp4 m4a mp3"    # what pull/prune/--list treat as "media"
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
  GDRIVE_REMOTE="" GDRIVE_ROOT="" GDRIVE_EXCLUDE_FILE="" GDRIVE_MEDIA_EXTENSIONS=""
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

# `--exclude-from <file>` when the conf names one (validated to exist).
# Used by push, which has no include rules, so plain excludes are safe.
gdrive_exclude_flags() {
  GDRIVE_EXCLUDE_FLAGS=()
  [[ -n "${GDRIVE_EXCLUDE_FILE}" ]] || return 0
  [[ -f "${GDRIVE_EXCLUDE_FILE}" ]] \
    || gdrive_die "GDRIVE_EXCLUDE_FILE=${GDRIVE_EXCLUDE_FILE} not found under ${GDRIVE_REPO_ROOT}"
  GDRIVE_EXCLUDE_FLAGS=(--exclude-from "${GDRIVE_REPO_ROOT}/${GDRIVE_EXCLUDE_FILE}")
}

# `--filter-from <generated file>` selecting media only: the push exclude
# list first (as `- pattern` rules), then `+ *.ext` per media extension, then
# `- *`. rclone applies filter rules in order, first match wins, and it does
# NOT define the order of mixed --include/--exclude flags, so one ordered
# filter file is the only reliable way to combine the two.
gdrive_media_filter_flags() {
  local f="${GDRIVE_TMPDIR}/media.filter" ext
  : > "${f}"
  if [[ -n "${GDRIVE_EXCLUDE_FILE}" ]]; then
    [[ -f "${GDRIVE_EXCLUDE_FILE}" ]] \
      || gdrive_die "GDRIVE_EXCLUDE_FILE=${GDRIVE_EXCLUDE_FILE} not found under ${GDRIVE_REPO_ROOT}"
    command sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' -e 's/^/- /' \
      "${GDRIVE_REPO_ROOT}/${GDRIVE_EXCLUDE_FILE}" >> "${f}"
  fi
  for ext in ${GDRIVE_MEDIA_EXTENSIONS}; do
    echo "+ *.${ext}" >> "${f}"
  done
  echo "- *" >> "${f}"
  GDRIVE_MEDIA_FILTER_FLAGS=(--filter-from "${f}")
}

# True when the file name ends in one of the media extensions.
gdrive_is_media() {
  local name="$1" ext
  for ext in ${GDRIVE_MEDIA_EXTENSIONS}; do
    [[ "${name}" == *".${ext}" ]] && return 0
  done
  return 1
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

# `rclone lsjson --stat` for one remote path. Prints the Size on stdout and
# returns 0; returns 3 when the path is absent; any other code is a failed
# call (auth, quota, network) and must not be read as "absent".
gdrive_remote_size() {
  local rel="$1" out rc=0
  out="$(rclone lsjson --stat --no-modtime "${GDRIVE_DEST}/${rel}" \
    ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} 2>/dev/null)" || rc=$?
  [[ ${rc} -eq 0 ]] || return "${rc}"
  gdrive_json_is_dir "${out}" && return 3
  # rclone pretty-prints `lsjson --stat` ("Size": 123), so tolerate spaces.
  printf '%s\n' "${out}" | command sed -n 's/.*"Size": *\([0-9-]*\).*/\1/p' | command head -n 1
}

# True when an `lsjson --stat` blob describes a directory.
gdrive_json_is_dir() {
  printf '%s\n' "$1" | command grep -q '"IsDir": *true'
}

# True when the remote path is a directory.
gdrive_remote_is_dir() {
  local rel="$1" out
  out="$(rclone lsjson --stat --no-modtime "${GDRIVE_DEST}/${rel}" \
    ${GDRIVE_RCLONE_COMMON[@]+"${GDRIVE_RCLONE_COMMON[@]}"} 2>/dev/null)" || return 1
  gdrive_json_is_dir "${out}"
}

# Lists local media files under a relative path (a file or a directory),
# one per line, relative to the repo root.
gdrive_local_media_under() {
  local rel="$1"
  if [[ -f "${rel}" ]]; then
    printf '%s\n' "${rel}"
    return 0
  fi
  [[ -d "${rel}" ]] || return 0
  local ext args=() first=1
  for ext in ${GDRIVE_MEDIA_EXTENSIONS}; do
    if [[ ${first} -eq 1 ]]; then first=0; else args+=(-o); fi
    args+=(-name "*.${ext}")
  done
  command find "${rel}" -type f \( "${args[@]}" \) | command sed 's|^\./||' | command sort
}

# True when git tracks the file (so it is not a Drive-only asset).
gdrive_git_tracked() {
  git ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}
