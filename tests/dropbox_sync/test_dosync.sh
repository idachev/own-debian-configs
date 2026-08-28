#!/bin/bash
# dosync must not rsync when the source dir is missing or empty.
# Otherwise --delete wipes the Dropbox dest (e.g. unmounted private docs).

set -u

SYNC_DIR="${HOME}/Dropbox/sync"
LINUX_UTILS="${SYNC_DIR}/sync_utils.sh"
OSX_UTILS="${SYNC_DIR}/sync_utils_osx.sh"

PASS=0
FAIL=0

assert_file() {
  local name="$1"
  local path="$2"
  if [ -f "${path}" ]; then
    PASS=$((PASS + 1))
    echo "PASS  ${name}"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  ${name} (missing ${path})"
  fi
}

assert_missing_file() {
  local name="$1"
  local path="$2"
  if [ ! -f "${path}" ]; then
    PASS=$((PASS + 1))
    echo "PASS  ${name}"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  ${name} (still present ${path})"
  fi
}

run_dosync() {
  local utils="$1"
  local src="$2"
  local dst="$3"
  # shellcheck disable=SC1090
  source "${utils}"
  OPT_PREVIEW=""
  dosync "${src}" "${dst}"
}

echo "=== dropbox_sync dosync empty source ==="

if [ ! -f "${LINUX_UTILS}" ] || [ ! -f "${OSX_UTILS}" ]; then
  echo "FAIL  sync utils missing under ${SYNC_DIR}"
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test_dosync.XXXXXX")"
trap 'command rm -rf "${TMP}"' EXIT

# --- linux: empty source must leave dest file ---
L_EMPTY_SRC="${TMP}/linux_empty_src"
L_EMPTY_DST="${TMP}/linux_empty_dst"
command mkdir -p "${L_EMPTY_SRC}" "${L_EMPTY_DST}"
echo keep > "${L_EMPTY_DST}/keep.txt"
run_dosync "${LINUX_UTILS}" "${L_EMPTY_SRC}/" "${L_EMPTY_DST}/"
assert_file "linux empty source keeps dest" "${L_EMPTY_DST}/keep.txt"

# --- osx: empty source must leave dest file ---
O_EMPTY_SRC="${TMP}/osx_empty_src"
O_EMPTY_DST="${TMP}/osx_empty_dst"
command mkdir -p "${O_EMPTY_SRC}" "${O_EMPTY_DST}"
echo keep > "${O_EMPTY_DST}/keep.txt"
run_dosync "${OSX_UTILS}" "${O_EMPTY_SRC}/" "${O_EMPTY_DST}/"
assert_file "osx empty source keeps dest" "${O_EMPTY_DST}/keep.txt"

# --- linux: .DS_Store-only source must leave dest file ---
L_DS_SRC="${TMP}/linux_ds_src"
L_DS_DST="${TMP}/linux_ds_dst"
command mkdir -p "${L_DS_SRC}" "${L_DS_DST}"
command touch "${L_DS_SRC}/.DS_Store"
echo keep > "${L_DS_DST}/keep.txt"
run_dosync "${LINUX_UTILS}" "${L_DS_SRC}/" "${L_DS_DST}/"
assert_file "linux .DS_Store-only source keeps dest" "${L_DS_DST}/keep.txt"

# --- osx: .DS_Store-only source must leave dest file ---
O_DS_SRC="${TMP}/osx_ds_src"
O_DS_DST="${TMP}/osx_ds_dst"
command mkdir -p "${O_DS_SRC}" "${O_DS_DST}"
command touch "${O_DS_SRC}/.DS_Store"
echo keep > "${O_DS_DST}/keep.txt"
run_dosync "${OSX_UTILS}" "${O_DS_SRC}/" "${O_DS_DST}/"
assert_file "osx .DS_Store-only source keeps dest" "${O_DS_DST}/keep.txt"

# --- linux: missing source must leave dest file ---
L_MISS_SRC="${TMP}/linux_missing_src"
L_MISS_DST="${TMP}/linux_missing_dst"
command mkdir -p "${L_MISS_DST}"
echo keep > "${L_MISS_DST}/keep.txt"
run_dosync "${LINUX_UTILS}" "${L_MISS_SRC}/" "${L_MISS_DST}/"
assert_file "linux missing source keeps dest" "${L_MISS_DST}/keep.txt"

# --- osx: missing source must leave dest file ---
O_MISS_SRC="${TMP}/osx_missing_src"
O_MISS_DST="${TMP}/osx_missing_dst"
command mkdir -p "${O_MISS_DST}"
echo keep > "${O_MISS_DST}/keep.txt"
run_dosync "${OSX_UTILS}" "${O_MISS_SRC}/" "${O_MISS_DST}/"
assert_file "osx missing source keeps dest" "${O_MISS_DST}/keep.txt"

# --- linux: non-empty source still syncs and --delete still works ---
L_SRC="${TMP}/linux_src"
L_DST="${TMP}/linux_dst"
command mkdir -p "${L_SRC}" "${L_DST}"
echo hello > "${L_SRC}/hello.txt"
echo stale > "${L_DST}/stale.txt"
run_dosync "${LINUX_UTILS}" "${L_SRC}/" "${L_DST}/"
assert_file "linux non-empty copies file" "${L_DST}/hello.txt"
assert_missing_file "linux non-empty deletes stale dest" "${L_DST}/stale.txt"

# --- osx: non-empty source still syncs and --delete still works ---
O_SRC="${TMP}/osx_src"
O_DST="${TMP}/osx_dst"
command mkdir -p "${O_SRC}" "${O_DST}"
echo hello > "${O_SRC}/hello.txt"
echo stale > "${O_DST}/stale.txt"
run_dosync "${OSX_UTILS}" "${O_SRC}/" "${O_DST}/"
assert_file "osx non-empty copies file" "${O_DST}/hello.txt"
assert_missing_file "osx non-empty deletes stale dest" "${O_DST}/stale.txt"

echo
echo "pass=${PASS} fail=${FAIL}"
[ "${FAIL}" -eq 0 ]
