#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_DIR=$1

if [ ! -d "${TARGET_DIR}" ]; then
  echo -e "Expecting valid dir: ${TARGET_DIR}"
  exit 1
fi

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
LOG_STAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${TARGET_DIR}/cleanup_develop_before_backup-dry-run-${LOG_STAMP}.log"

echo "Wrote log: ${LOG_FILE}" >&2

{
  echo "# cleanup_develop_before_backup dry-run"
  echo "# target=${TARGET_DIR}"
  echo "# started=${LOG_STAMP}"
  echo
} > "${LOG_FILE}"

cd "${TARGET_DIR}"

# Deliberately not cleaned: whole tmp/, out/, dist/, .idea, .wrangler,
# coverage-report (Maven module), CMake/docker/scripts dirs named build.
# Tree-specific names live in TARGET_DIR/cleanup_before_backup.dirs.

# Do not walk .git or node_modules. Print the match itself, then prune.
find_pruned() {
  find . \( -name .git -o -name node_modules \) -prune -o -type d "$@" -prune -print0
}

run_helper() {
  local helper=$1
  shift
  find_pruned "$@" | xargs -0 -r -l1 "${DIR}/${helper}"
}

# Optional extra names/paths from TARGET_DIR/cleanup_before_backup.dirs
run_listed_dirs() {
  local extra="${TARGET_DIR}/cleanup_before_backup.dirs"
  local line
  [ -s "${extra}" ] || return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "${line}" ] && continue
    case "${line}" in
      /*|*..*|*'*'*|*'?'*|*'['*) continue ;;
    esac
    if printf '%s' "${line}" | command grep -q '/'; then
      find . \( -name .git -o -name node_modules \) -prune \
        -o -type d -path "*/${line}" -prune -print0 | \
        xargs -0 -r -l1 "${DIR}/cleanup_develop_dir_if_listed.sh"
    else
      run_helper cleanup_develop_dir_if_listed.sh -name "${line}"
    fi
  done < "${extra}"
}

{
  run_helper cleanup_develop_dir_if_maven_target.sh -name target

  find . -name .git -prune -o -type d -name node_modules -prune -print0 | \
    xargs -0 -r -l1 "${DIR}/cleanup_develop_dir_if_npm_modules.sh"

  # venv and .venv (both match pyvenv.cfg via cleanup_develop_dir_if_venv.sh)
  run_helper cleanup_develop_dir_if_venv.sh \( -name venv -o -name .venv \)

  run_helper cleanup_develop_dir_if_gradle.sh -name .gradle
  run_helper cleanup_develop_dir_if_gradle_build.sh -name build

  # Skip caches already covered by .venv / venv / node_modules / target.
  find . \( -name .git -o -name node_modules -o -name .venv -o -name venv -o -name target \) -prune \
    -o -type d \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache -o -name htmlcov \) \
    -prune -print0 | \
    xargs -0 -r -l1 "${DIR}/cleanup_develop_dir_if_python_cache.sh"

  run_helper cleanup_develop_dir_if_js_cache.sh \
    \( -name .next -o -name .open-next -o -name .nx \
       -o -name .turbo -o -name .parcel-cache \)

  run_listed_dirs
} | tee -a "${LOG_FILE}"
