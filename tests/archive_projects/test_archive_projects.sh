#!/bin/bash
# Fixture test for archive_projects.sh and verify_project_archives.py
#
# Usage:
#   ~/bin/tests/archive_projects/test_archive_projects.sh

set -u

ARCHIVE_SH="$HOME/bin/archive_projects.sh"
VERIFY_PY="$HOME/bin/verify_project_archives.py"

if [ ! -x "$ARCHIVE_SH" ]; then
  echo "ERROR: $ARCHIVE_SH not found or not executable" >&2
  exit 2
fi
if [ ! -f "$VERIFY_PY" ]; then
  echo "ERROR: $VERIFY_PY not found" >&2
  exit 2
fi

PASS=0
FAIL=0
C_GREEN=$'\e[32m'
C_RED=$'\e[31m'
C_OFF=$'\e[0m'

ROOT=$(mktemp -d /tmp/archive-projects-test-XXXXXX)
trap 'rm -rf "$ROOT"' EXIT

ok() {
  echo "${C_GREEN}PASS${C_OFF} $1"
  PASS=$((PASS + 1))
}
bad() {
  echo "${C_RED}FAIL${C_OFF} $1"
  FAIL=$((FAIL + 1))
}

mkdir -p "$ROOT/workspace/app/.git" "$ROOT/workspace/app/src"
printf 'hello\n' > "$ROOT/workspace/app/README"
printf 'ref: refs/heads/main\n' > "$ROOT/workspace/app/.git/HEAD"
mkdir -p "$ROOT/workspace/app/module"
printf '<project/>\n' > "$ROOT/workspace/app/module/pom.xml"
command find "$ROOT/workspace/app" -type f -exec touch -t 201901010101 {} +
touch -t 202001020304 "$ROOT/workspace/app/README"

mkdir -p "$ROOT/workspace/other/src" "$ROOT/workspace/other/docs"
printf 'desc\n' > "$ROOT/workspace/other/docs/README.md"
printf 'code\n' > "$ROOT/workspace/other/src/main.c"
command find "$ROOT/workspace/other" -type f -exec touch -t 202001010101 {} +
touch -t 202103040506 "$ROOT/workspace/other/src/main.c"

dry=$("$ARCHIVE_SH" "$ROOT/workspace" 2>&1) || {
  bad "dry-run exit"
  echo "$dry"
}

echo "$dry" | grep -q 'app_20200102.tgz' && ok "dry-run dated git project" || bad "dry-run dated git project: $dry"
echo "$dry" | grep -q 'other_20210304.tgz' && ok "dry-run dated src+docs project" || bad "dry-run dated src+docs"
echo "$dry" | grep -q 'module' && bad "nested pom.xml should be skipped" || ok "nested pom.xml skipped"

"$ARCHIVE_SH" --archive "$ROOT/workspace" >/dev/null || bad "archive exit"
if [ -f "$ROOT/workspace/app_20200102.tgz" ]; then
  ok "created app_20200102.tgz"
else
  bad "missing app_20200102.tgz"
fi
if [ -f "$ROOT/workspace/other_20210304.tgz" ]; then
  ok "created other_20210304.tgz"
else
  bad "missing other_20210304.tgz"
fi

if command python3 "$VERIFY_PY" --quiet "$ROOT/workspace/app_20200102.tgz"; then
  ok "verify app match"
else
  bad "verify app match"
fi

if command python3 - <<'PY'
import importlib.util
import os
spec = importlib.util.spec_from_file_location(
    "v", os.environ["HOME"] + "/bin/verify_project_archives.py"
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.live_stem("app_20200102.tgz") == "app"
assert m.live_stem("app.tgz") == "app"
PY
then
  ok "live_stem helpers"
else
  bad "live_stem helpers"
fi

# --remove content-verifies then deletes
mkdir -p "$ROOT/one/proj/.git"
printf 'x\n' > "$ROOT/one/proj/file.txt"
touch -t 201805060708 "$ROOT/one/proj/file.txt"
"$ARCHIVE_SH" --archive --remove "$ROOT/one" >/dev/null || bad "archive --remove exit"
if [ -f "$ROOT/one/proj_20180506.tgz" ] && [ ! -e "$ROOT/one/proj" ]; then
  ok "archive --remove deleted live dir"
else
  bad "archive --remove did not delete live dir"
fi

# exact dir name ending in _YYYYMMDD still matches
mkdir -p "$ROOT/datedname/foo_20180117"
printf 'z\n' > "$ROOT/datedname/foo_20180117/a.txt"
command tar -C "$ROOT/datedname" -czf "$ROOT/datedname/foo_20180117.tgz" foo_20180117
if command python3 "$VERIFY_PY" --quiet "$ROOT/datedname/foo_20180117.tgz"; then
  ok "verify prefers exact stem foo_20180117"
else
  bad "verify prefers exact stem foo_20180117"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
