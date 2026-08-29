#!/bin/bash
# Fixture test for ~/bin/cleanup_develop_before_backup.sh
#
# Builds a synthetic tree with both regenerable caches and source/data
# lookalikes, then checks the dry-run rm list.
#
# Usage:
#   ~/bin/tests/cleanup_develop_before_backup/test_cleanup_develop_before_backup.sh

set -u

SCRIPT="$HOME/bin/cleanup_develop_before_backup.sh"

if [ ! -x "$SCRIPT" ]; then
  echo "ERROR: $SCRIPT not found or not executable" >&2
  exit 2
fi

PASS=0
FAIL=0

C_GREEN=$'\e[32m'
C_RED=$'\e[31m'
C_OFF=$'\e[0m'

ROOT=$(mktemp -d /tmp/cleanup-develop-test-XXXXXX)
trap 'rm -rf "$ROOT"' EXIT

mkdir_p() { mkdir -p "$ROOT/$1"; }
touch_p() {
  mkdir -p "$(dirname "$ROOT/$1")"
  printf 'x\n' > "$ROOT/$1"
}

# --- regenerable caches (must be listed for rm) ---
mkdir_p maven-mod/target/classes
touch_p maven-mod/pom.xml

mkdir_p js-app/node_modules/leftpad
touch_p js-app/package.json
mkdir_p js-app/node_modules/foo/node_modules/nested

mkdir_p py-app/.venv/lib/python3.12/site-packages
touch_p py-app/.venv/pyvenv.cfg
mkdir_p py-app/.venv/lib/python3.12/site-packages/mypy/typeshed/stdlib/venv
mkdir_p py-app/.venv/lib/python3.12/site-packages/certifi/__pycache__
mkdir_p py-app2/venv/lib
touch_p py-app2/venv/pyvenv.cfg

mkdir_p gradle-mod/.gradle/vcs-1
mkdir_p gradle-mod/build/libs
touch_p gradle-mod/build.gradle
touch_p gradle-mod/settings.gradle

mkdir_p gradle-kts/.gradle/8.14.2
mkdir_p gradle-kts/build/classes
touch_p gradle-kts/build.gradle.kts
touch_p gradle-kts/settings.gradle.kts

mkdir_p gradle-user-cache/.gradle/vcsWorkingDirs
touch_p gradle-user-cache/.gradle/vcsWorkingDirs/x

mkdir_p repo/tmp/claude-logs/run-1
touch_p repo/tmp/claude-logs/run-1/build.log

mkdir_p next-app/.next/cache
mkdir_p next-app/.open-next/server-functions
touch_p next-app/package.json
touch_p next-app/next.config.ts
touch_p next-app/open-next.config.ts

mkdir_p py-app/pkg/__pycache__
mkdir_p py-app/.mypy_cache
mkdir_p py-app/.pytest_cache
mkdir_p py-app/.ruff_cache
mkdir_p py-app/htmlcov
touch_p py-app/htmlcov/index.html
touch_p py-app/pyproject.toml

mkdir_p js-app/coverage/lcov-report
touch_p js-app/coverage/lcov.info
mkdir_p js-app/.vite/deps
mkdir_p js-app/.turbo
mkdir_p js-app/.parcel-cache
mkdir_p js-app/storybook-static
touch_p js-app/storybook-static/index.html
mkdir_p js-app/.playwright-mcp

mkdir_p nx-app/.nx/cache
touch_p nx-app/nx.json
touch_p nx-app/package.json

# Storybook output committed to git must not be deleted.
mkdir_p tracked-sb/storybook-static
touch_p tracked-sb/package.json
touch_p tracked-sb/storybook-static/index.html
command git -C "$ROOT/tracked-sb" init -q
command git -C "$ROOT/tracked-sb" add storybook-static/index.html

mkdir_p tracked-cov/coverage/lcov-report
touch_p tracked-cov/package.json
touch_p tracked-cov/coverage/lcov.info
command git -C "$ROOT/tracked-cov" init -q
command git -C "$ROOT/tracked-cov" add coverage/lcov.info

# --- source / data lookalikes (must NOT be listed for rm) ---
mkdir_p hex/src/main/java/app/ports/out
touch_p hex/src/main/java/app/ports/out/SavePort.java
mkdir_p hex/src/main/java/app/domain/build
touch_p hex/src/main/java/app/domain/build/BuildPlan.java

mkdir_p vendor/jquery/dist
touch_p vendor/jquery/dist/jquery.js

mkdir_p site/tmp/photos
touch_p site/tmp/photos/img.jpg
mkdir_p site/tmp/exports
touch_p site/tmp/exports/book.pdf

mkdir_p maven-mod/coverage-report/src/main/java
touch_p maven-mod/coverage-report/pom.xml
touch_p maven-mod/coverage-report/src/main/java/ReportMojo.java

mkdir_p cmake-proj/build/CMakeFiles
touch_p cmake-proj/CMakeLists.txt
touch_p cmake-proj/build/CMakeCache.txt

mkdir_p docker/build
touch_p docker/build/Dockerfile

mkdir_p scripts/build
touch_p scripts/package.json
touch_p scripts/build/inubit-release-export.sh

mkdir_p fake-git/.git/refs/remotes/origin/build
touch_p fake-git/.git/refs/remotes/origin/build/HEAD

mkdir_p idea-proj/.idea
touch_p idea-proj/.idea/workspace.xml
mkdir_p worca-proj/.worca/results
touch_p worca-proj/.worca/active_run
mkdir_p cf-app/.wrangler/state
touch_p cf-app/wrangler.toml

mkdir_p rust-like/target/debug
touch_p rust-like/Cargo.toml

mkdir_p empty-coverage/coverage
touch_p empty-coverage/package.json

mkdir_p hex/src/main/java/app/adapters/out
touch_p hex/src/main/java/app/adapters/out/Repo.java

mkdir_p random/out
touch_p random/out/crops.bin

printf '%s\n' \
  'storybook-static' \
  '.vite' \
  'coverage' \
  'tmp/claude-logs' \
  > "$ROOT/cleanup_before_backup.dirs"

MUST_DELETE='
./maven-mod/target
./js-app/node_modules
./py-app/.venv
./py-app2/venv
./gradle-mod/.gradle
./gradle-mod/build
./gradle-kts/.gradle
./gradle-kts/build
./gradle-user-cache/.gradle
./repo/tmp/claude-logs
./next-app/.next
./next-app/.open-next
./py-app/pkg/__pycache__
./py-app/.mypy_cache
./py-app/.pytest_cache
./py-app/.ruff_cache
./py-app/htmlcov
./js-app/coverage
./js-app/.vite
./js-app/.turbo
./js-app/.parcel-cache
./js-app/storybook-static
./nx-app/.nx
'

MUST_KEEP='
./hex/src/main/java/app/ports/out
./hex/src/main/java/app/adapters/out
./hex/src/main/java/app/domain/build
./vendor/jquery/dist
./site/tmp/photos
./site/tmp/exports
./maven-mod/coverage-report
./maven-mod/coverage-report/src
./cmake-proj/build
./docker/build
./scripts/build
./fake-git/.git/refs/remotes/origin/build
./idea-proj/.idea
./worca-proj/.worca
./js-app/.playwright-mcp
./cf-app/.wrangler
./tracked-sb/storybook-static
./tracked-cov/coverage
./rust-like/target
./empty-coverage/coverage
./random/out
./js-app/node_modules/foo/node_modules
./py-app/.venv/lib/python3.12/site-packages/mypy/typeshed/stdlib/venv
./py-app/.venv/lib/python3.12/site-packages/certifi/__pycache__
'

echo "Running $SCRIPT on $ROOT"
STDERR_FILE="$ROOT/stderr.txt"
OUT=$("$SCRIPT" "$ROOT" 2>"$STDERR_FILE") || true

RM_LIST=$(printf '%s\n' "$OUT" | command grep '^rm -rf ' | command sed 's/^rm -rf "//;s/"$//' | command sort -u)

echo
echo "=== dry-run rm paths ==="
printf '%s\n' "$RM_LIST"

check_delete() {
  local path="$1"
  if printf '%s\n' "$RM_LIST" | command grep -Fxq "$path"; then
    PASS=$((PASS + 1))
    printf '  %sPASS%s  delete  %s\n' "$C_GREEN" "$C_OFF" "$path"
  else
    FAIL=$((FAIL + 1))
    printf '  %sFAIL%s  expected delete, missing  %s\n' "$C_RED" "$C_OFF" "$path"
  fi
}

check_keep() {
  local path="$1"
  if printf '%s\n' "$RM_LIST" | command grep -Fxq "$path"; then
    FAIL=$((FAIL + 1))
    printf '  %sFAIL%s  must keep, but listed for rm  %s\n' "$C_RED" "$C_OFF" "$path"
  else
    PASS=$((PASS + 1))
    printf '  %sPASS%s  keep    %s\n' "$C_GREEN" "$C_OFF" "$path"
  fi
}

echo
echo "=== must delete ==="
while IFS= read -r path; do
  [ -z "$path" ] && continue
  check_delete "$path"
done <<< "$MUST_DELETE"

echo
echo "=== must keep ==="
while IFS= read -r path; do
  [ -z "$path" ] && continue
  check_keep "$path"
done <<< "$MUST_KEEP"

echo
echo "=== log file ==="
LOG_MATCHES=$(command ls -1 "$ROOT"/cleanup_develop_before_backup-dry-run-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].log 2>/dev/null)
LOG_COUNT=$(printf '%s\n' "$LOG_MATCHES" | command grep -c . || true)
if [ "$LOG_COUNT" -eq 1 ]; then
  PASS=$((PASS + 1))
  printf '  %sPASS%s  log file  %s\n' "$C_GREEN" "$C_OFF" "$(basename "$LOG_MATCHES")"
else
  FAIL=$((FAIL + 1))
  printf '  %sFAIL%s  expected 1 timestamped log in target dir, got %s\n' "$C_RED" "$C_OFF" "$LOG_COUNT"
fi

if [ "$LOG_COUNT" -eq 1 ]; then
  LOG_RM=$(command grep '^rm -rf ' "$LOG_MATCHES" | command sed 's/^rm -rf "//;s/"$//' | command sort -u)
  if [ "$LOG_RM" = "$RM_LIST" ]; then
    PASS=$((PASS + 1))
    printf '  %sPASS%s  log rm list matches stdout\n' "$C_GREEN" "$C_OFF"
  else
    FAIL=$((FAIL + 1))
    printf '  %sFAIL%s  log rm list differs from stdout\n' "$C_RED" "$C_OFF"
  fi
fi

if printf '%s\n' "$OUT" | command grep -q 'Wrote log:'; then
  FAIL=$((FAIL + 1))
  printf '  %sFAIL%s  stdout must not contain log path (breaks doit)\n' "$C_RED" "$C_OFF"
else
  PASS=$((PASS + 1))
  printf '  %sPASS%s  stdout has no log path\n' "$C_GREEN" "$C_OFF"
fi

if command grep -q "Wrote log: $ROOT/cleanup_develop_before_backup-dry-run-" "$STDERR_FILE"; then
  PASS=$((PASS + 1))
  printf '  %sPASS%s  stderr prints log path\n' "$C_GREEN" "$C_OFF"
else
  FAIL=$((FAIL + 1))
  printf '  %sFAIL%s  stderr missing Wrote log path\n' "$C_RED" "$C_OFF"
  command cat "$STDERR_FILE"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
