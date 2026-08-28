#!/usr/bin/env bash
# Find subdirectories that look like a standalone project and archive each as .tgz.
#
# A directory is a project when any of these hold:
#   - VCS metadata: .git, .hg, .svn, .bzr
#   - src/ plus docs/ that holds a description (README*, DESCRIPTION*, *.md, *.rst, *.txt)
#   - a root build/manifest file (see --help)
#
# Nested projects are skipped by default (outermost wins). The scan root
# itself is included when it looks like a project.
# Archive name is {name}_{YYYYMMDD}.tgz. The date is the newest file mtime
# inside the project, same rule as mc_archive_dir.sh (.idea and .git
# index/logs/refs are ignored).
# Default mode is dry-run. Nothing is written until --archive (or doit).
#
# Usage:
#   archive_projects.sh [options] [ROOT]
#   archive_projects.sh --archive [ROOT]
#   archive_projects.sh doit [ROOT]
#
# ROOT defaults to the current working directory.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

usage() {
  command cat <<'EOF'
Find project directories under ROOT and archive each as .tgz.

A directory is a project when it has:
  - .git, .hg, .svn, or .bzr
  - src/ plus docs/ with a description file
  - a root manifest: pom.xml, build.gradle, settings.gradle, package.json,
    setup.py, pyproject.toml, Cargo.toml, go.mod, composer.json, Gemfile,
    CMakeLists.txt, mix.exs, pubspec.yaml, Pipfile

Nested projects are skipped (outermost wins). Pass --nested to keep them.
ROOT itself is archived when it looks like a project.

The .tgz name is {name}_{YYYYMMDD}.tgz. YYYYMMDD is the newest file mtime
in the project (ignores .idea and .git index/logs/refs), matching
mc_archive_dir.sh.

Usage:
  archive_projects.sh [options] [ROOT]

Options:
  -n, --dry-run         List candidates only (default)
  -a, --archive         Create .tgz files
      doit              Same as --archive
      --remove          After a successful archive, content-verify then delete the original directory
      --force           Overwrite an existing .tgz
      --nested          Also archive projects inside another project
      --archived-subdir Write parent/__archived__/name_YYYYMMDD.tgz
      --out DIR         Write every .tgz into DIR (names use ROOT-relative path + date)
      --max-depth N     Limit find depth (from ROOT)
      --exclude NAME    Extra directory name to prune (repeatable)
  -h, --help            Show this help
  -x                    Trace execution (bash -x)

ROOT defaults to the current working directory.

Examples:
  archive_projects.sh
  archive_projects.sh --archive ~/work
  archive_projects.sh --archive --out /backup/projects ~/work
  archive_projects.sh --archive --archived-subdir --remove ~/work
EOF
}

MODE="dry-run"
REMOVE=0
FORCE=0
NESTED=0
ARCHIVED_SUBDIR=0
OUT_DIR=""
MAX_DEPTH=""
ROOT=""
EXTRA_EXCLUDES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -n|--dry-run)
      MODE="dry-run"
      shift
      ;;
    -a|--archive)
      MODE="archive"
      shift
      ;;
    doit)
      MODE="archive"
      shift
      ;;
    --remove)
      REMOVE=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --nested)
      NESTED=1
      shift
      ;;
    --archived-subdir)
      ARCHIVED_SUBDIR=1
      shift
      ;;
    --out)
      OUT_DIR="${2:?--out requires a directory}"
      shift 2
      ;;
    --max-depth)
      MAX_DEPTH="${2:?--max-depth requires N}"
      shift 2
      ;;
    --exclude)
      EXTRA_EXCLUDES+=("${2:?--exclude requires a name}")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$ROOT" ]]; then
        echo "Unexpected extra argument: $1" >&2
        exit 2
      fi
      ROOT="$1"
      shift
      ;;
  esac
done

if [[ $# -gt 0 && -z "$ROOT" ]]; then
  ROOT="$1"
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "Unexpected extra argument: $1" >&2
  exit 2
fi

if [[ -n "$ROOT" ]]; then
  if [[ ! -d "$ROOT" ]]; then
    echo "ROOT is not a directory: $ROOT" >&2
    exit 2
  fi
  ROOT="$(cd "$ROOT" && pwd)"
else
  ROOT="$(pwd)"
fi

if [[ "$REMOVE" -eq 1 && "$MODE" != "archive" ]]; then
  echo "--remove needs --archive (or doit)" >&2
  exit 2
fi

if [[ -n "$OUT_DIR" && "$OUT_DIR" != /* ]]; then
  OUT_DIR="$(pwd)/$OUT_DIR"
fi

TAR_EXTRA=()
if command tar --help 2>/dev/null | command grep -q -- '--ignore-failed-read'; then
  TAR_EXTRA+=(--ignore-failed-read)
fi

VERIFY_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_project_archives.py"

if command stat -c '%Y' "$ROOT" >/dev/null 2>&1; then
  STAT_MTIME=(stat -c '%Y')
  epoch_to_yyyymmdd() { command date -d "@$1" +%Y%m%d; }
else
  STAT_MTIME=(stat -f '%m')
  epoch_to_yyyymmdd() { command date -r "$1" +%Y%m%d; }
fi

PRUNE_NAMES=(
  __archived__
  node_modules
  __pycache__
  .gradle
  .idea
  .venv
  venv
  .tox
  .mypy_cache
  bower_components
)
if [[ ${#EXTRA_EXCLUDES[@]} -gt 0 ]]; then
  PRUNE_NAMES+=("${EXTRA_EXCLUDES[@]}")
fi

FIND_DEPTH=()
if [[ -n "$MAX_DEPTH" ]]; then
  FIND_DEPTH=(-maxdepth "$MAX_DEPTH")
fi

PRUNE_OR=()
for name in "${PRUNE_NAMES[@]}"; do
  if [[ ${#PRUNE_OR[@]} -gt 0 ]]; then
    PRUNE_OR+=(-o)
  fi
  PRUNE_OR+=(-name "$name")
done

declare -A REASON=()

add_reason() {
  local dir="$1"
  local why="$2"
  dir="${dir%/}"
  [[ -d "$dir" ]] || return 0
  case "$dir" in
    "$ROOT"|"$ROOT"/*) ;;
    *) return 0 ;;
  esac
  if [[ -n "${REASON[$dir]:-}" ]]; then
    case ",${REASON[$dir]}," in
      *,"$why",*) return 0 ;;
    esac
    REASON[$dir]="${REASON[$dir]},${why}"
    return 0
  fi
  REASON[$dir]="$why"
}

has_docs_description() {
  local docs="$1"
  [[ -d "$docs" ]] || return 1
  local hit
  hit="$(command find "$docs" -maxdepth 2 -type f \( \
    -iname 'README*' -o -iname 'DESCRIPTION*' -o \
    -iname '*.md' -o -iname '*.rst' -o -iname '*.txt' \
    \) -print -quit 2>/dev/null || true)"
  [[ -n "$hit" ]]
}

find_print0() {
  command find "$ROOT" "${FIND_DEPTH[@]}" \
    \( "${PRUNE_OR[@]}" \) -prune -o "$@"
}

collect_vcs() {
  local vcs parent why
  while IFS= read -r -d '' vcs; do
    parent="$(command dirname "$vcs")"
    why="$(command basename "$vcs")"
    add_reason "$parent" "$why"
  done < <(find_print0 \( \( \
      -name .git -o -name .hg -o -name .svn -o -name .bzr \
    \) \( -type d -o -type f \) -print0 -prune \) 2>/dev/null)
}

collect_build_files() {
  local file parent
  while IFS= read -r -d '' file; do
    parent="$(command dirname "$file")"
    add_reason "$parent" "$(command basename "$file")"
  done < <(find_print0 \( -type f \( \
      -name pom.xml -o -name build.gradle -o -name settings.gradle \
      -o -name package.json -o -name setup.py -o -name pyproject.toml \
      -o -name Cargo.toml -o -name go.mod -o -name composer.json \
      -o -name Gemfile -o -name CMakeLists.txt -o -name mix.exs \
      -o -name pubspec.yaml -o -name Pipfile \
    \) -print0 \) 2>/dev/null)
}

collect_src_docs() {
  local srcdir parent
  while IFS= read -r -d '' srcdir; do
    parent="$(command dirname "$srcdir")"
    if has_docs_description "$parent/docs"; then
      add_reason "$parent" "src+docs"
    fi
  done < <(find_print0 \( -type d -name src -print0 -prune \) 2>/dev/null)
}

collect_vcs
collect_build_files
collect_src_docs

if [[ ${#REASON[@]} -eq 0 ]]; then
  echo "No project directories under $ROOT"
  exit 0
fi

mapfile -t ALL_DIRS < <(printf '%s\n' "${!REASON[@]}" | LC_ALL=C sort)

KEEP=()
SKIPPED_NESTED=()
for dir in "${ALL_DIRS[@]}"; do
  nested_of=""
  if [[ "$NESTED" -eq 0 ]]; then
    for kept in "${KEEP[@]+"${KEEP[@]}"}"; do
      if [[ "$dir" == "$kept"/* ]]; then
        nested_of="$kept"
        break
      fi
    done
  fi
  if [[ -n "$nested_of" ]]; then
    SKIPPED_NESTED+=("$dir")
    continue
  fi
  KEEP+=("$dir")
done

relpath() {
  local path="$1"
  if [[ "$path" == "$ROOT" ]]; then
    printf '%s\n' "$(command basename "$ROOT")"
  elif [[ "$path" == "$ROOT"/* ]]; then
    printf '%s\n' "${path#"$ROOT"/}"
  else
    printf '%s\n' "$path"
  fi
}

# Newest regular-file mtime as YYYYMMDD. Same skip rules as mc_archive_dir.sh.
last_date_for_dir() {
  local dir="$1"
  local epoch date
  epoch="$(command find "$dir" -type f \
    ! -path '*/.idea/*' \
    ! -path '*/.git/index*' \
    ! -path '*/.git/logs*' \
    ! -path '*/.git/refs*' \
    -exec "${STAT_MTIME[@]}" {} + 2>/dev/null \
    | command sort -n \
    | command tail -n 1 \
    || true)"
  if [[ -z "$epoch" ]]; then
    date="$(command date +%Y%m%d)"
  else
    date="$(epoch_to_yyyymmdd "$epoch")"
  fi
  printf '%s\n' "$date"
}

archive_path_for() {
  local dir="$1"
  local date="$2"
  local parent base dest rel safe
  parent="$(command dirname "$dir")"
  base="$(command basename "$dir")"
  safe="${base// /_}"
  if [[ -n "$OUT_DIR" ]]; then
    rel="$(relpath "$dir")"
    rel="${rel// /_}"
    dest="$OUT_DIR/${rel//\//_}_${date}.tgz"
  elif [[ "$ARCHIVED_SUBDIR" -eq 1 ]]; then
    dest="$parent/__archived__/${safe}_${date}.tgz"
  else
    dest="$parent/${safe}_${date}.tgz"
  fi
  printf '%s\n' "$dest"
}

human_size() {
  command du -sh "$1" 2>/dev/null | command awk '{print $1}'
}

printf 'ROOT %s\n' "$ROOT"
printf 'MODE %s\n' "$MODE"
if [[ "$NESTED" -eq 1 ]]; then
  printf 'NESTED on\n'
fi
printf '\n'
printf '%-8s %-28s %s\n' "SIZE" "REASON" "PROJECT"
printf '%-8s %-28s %s\n' "----" "------" "-------"
printf '%8s %s\n' "" "-> TGZ"

FAILED=0
ARCHIVED=0
SKIPPED_EXISTS=0

for dir in "${KEEP[@]}"; do
  last_date="$(last_date_for_dir "$dir")"
  dest="$(archive_path_for "$dir" "$last_date")"
  size="$(human_size "$dir")"
  why="${REASON[$dir]}"
  printf '%-8s %-28s %s\n' \
    "${size:-?}" "$why" "$(relpath "$dir")"
  printf '%8s %s %s\n' "" "->" "$dest"

  if [[ "$MODE" != "archive" ]]; then
    continue
  fi

  if [[ -e "$dest" && "$FORCE" -eq 0 ]]; then
    echo "  skip: already exists (use --force): $dest"
    SKIPPED_EXISTS=$((SKIPPED_EXISTS + 1))
    continue
  fi

  command mkdir -p "$(command dirname "$dest")"
  parent="$(command dirname "$dir")"
  base="$(command basename "$dir")"
  tmp="${dest}.partial.$$"

  if ! command tar -C "$parent" \
      "${TAR_EXTRA[@]}" \
      --exclude="$(command basename "$dest")" \
      --exclude="$(command basename "$tmp")" \
      -czf "$tmp" "$base"; then
    echo "  error: tar failed for $dir" >&2
    command rm -f "$tmp"
    FAILED=$((FAILED + 1))
    continue
  fi

  if [[ ! -s "$tmp" ]]; then
    echo "  error: empty archive for $dir" >&2
    command rm -f "$tmp"
    FAILED=$((FAILED + 1))
    continue
  fi

  command mv -f "$tmp" "$dest"
  ARCHIVED=$((ARCHIVED + 1))
  echo "  wrote $(human_size "$dest") -> $dest"

  if [[ "$REMOVE" -eq 1 ]]; then
    if [[ ! -f "$VERIFY_SCRIPT" ]]; then
      echo "  error: $VERIFY_SCRIPT missing, kept $dir" >&2
      FAILED=$((FAILED + 1))
    elif command python3 "$VERIFY_SCRIPT" --quiet "$dest"; then
      command rm -rf "$dir"
      echo "  removed $dir"
    else
      echo "  error: content mismatch, kept $dir" >&2
      FAILED=$((FAILED + 1))
    fi
  fi
done

printf '\n%d project(s) selected\n' "${#KEEP[@]}"
if [[ ${#SKIPPED_NESTED[@]} -gt 0 ]]; then
  printf '%d nested project(s) skipped (pass --nested to include)\n' \
    "${#SKIPPED_NESTED[@]}"
fi

if [[ "$MODE" == "dry-run" ]]; then
  printf '\nDry run. To write archives:\n  %s --archive %s\n' "$0" "$ROOT"
else
  printf '%d archive(s) written\n' "$ARCHIVED"
  if [[ "$SKIPPED_EXISTS" -gt 0 ]]; then
    printf '%d skipped (already exists)\n' "$SKIPPED_EXISTS"
  fi
  if [[ "$FAILED" -gt 0 ]]; then
    printf '%d failed\n' "$FAILED" >&2
    exit 1
  fi
fi
