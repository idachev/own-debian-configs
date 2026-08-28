#!/bin/bash
# CLI contract for gocryptfs_storage_private_docs_osx.sh.
# Does not store a Keychain password or bootstrap the LaunchAgent.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OSX="${ROOT}/gocryptfs_storage_private_docs_osx.sh"
UNMOUNT="${ROOT}/gocryptfs_storage_private_docs_osx_unmount.sh"

PASS=0
FAIL=0

assert_exit() {
  local name="$1"
  local expected="$2"
  shift 2
  local actual=0
  "$@" >/tmp/gocryptfs_osx_out.txt 2>/tmp/gocryptfs_osx_err.txt || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1))
    echo "PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $name (exit $actual, expected $expected)"
    command cat /tmp/gocryptfs_osx_out.txt /tmp/gocryptfs_osx_err.txt
  fi
}

assert_stdout_grep() {
  local name="$1"
  local pattern="$2"
  shift 2
  if "$@" >/tmp/gocryptfs_osx_out.txt 2>/tmp/gocryptfs_osx_err.txt &&
    command grep -q -e "$pattern" /tmp/gocryptfs_osx_out.txt; then
    PASS=$((PASS + 1))
    echo "PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $name (no match for /$pattern/)"
    command cat /tmp/gocryptfs_osx_out.txt /tmp/gocryptfs_osx_err.txt
  fi
}

echo "=== gocryptfs_osx CLI ==="

if command bash -n "$OSX" && command bash -n "$UNMOUNT"; then
  PASS=$((PASS + 1))
  echo "PASS  bash -n"
else
  FAIL=$((FAIL + 1))
  echo "FAIL  bash -n"
fi

assert_exit "bogus" 2 "$OSX" bogus
assert_exit "help" 0 "$OSX" --help
assert_stdout_grep "help names keychain-set" "keychain-set" "$OSX" --help
assert_stdout_grep "help names agent-install" "agent-install" "$OSX" --help
assert_exit "status" 0 "$OSX" status
assert_stdout_grep "status names cipherdir" "storage_private_docs.crypt" "$OSX" status
assert_stdout_grep "status start stamp" "----- start status " "$OSX" status
assert_stdout_grep "status stop stamp" "----- stop status exit 0 " "$OSX" status

if "$OSX" status >/tmp/gocryptfs_osx_out.txt 2>/tmp/gocryptfs_osx_err.txt &&
  command grep -E '^----- start status [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ' /tmp/gocryptfs_osx_out.txt >/dev/null &&
  command grep -E '^----- stop status exit 0 [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ' /tmp/gocryptfs_osx_out.txt >/dev/null; then
  PASS=$((PASS + 1))
  echo "PASS  status stamps have date and time"
else
  FAIL=$((FAIL + 1))
  echo "FAIL  status stamps have date and time"
  command cat /tmp/gocryptfs_osx_out.txt /tmp/gocryptfs_osx_err.txt
fi

if "$OSX" --help >/tmp/gocryptfs_osx_out.txt 2>/tmp/gocryptfs_osx_err.txt &&
  ! command grep -F -e "----- start " /tmp/gocryptfs_osx_out.txt >/dev/null &&
  ! command grep -F -e "----- start " /tmp/gocryptfs_osx_err.txt >/dev/null; then
  PASS=$((PASS + 1))
  echo "PASS  help has no run stamp"
else
  FAIL=$((FAIL + 1))
  echo "FAIL  help has no run stamp"
  command cat /tmp/gocryptfs_osx_out.txt /tmp/gocryptfs_osx_err.txt
fi

if command grep -E 'sudo launchctl (load|unload)' "$OSX" "$UNMOUNT" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  scripts have no sudo load/unload"
else
  PASS=$((PASS + 1))
  echo "PASS  scripts have no sudo load/unload"
fi

if command grep -E '^[^#]*fusermount' "$OSX" "$UNMOUNT" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  scripts use umount, not fusermount"
else
  PASS=$((PASS + 1))
  echo "PASS  scripts use umount, not fusermount"
fi

if command grep -E 'KeepAlive' "$OSX" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  LaunchAgent has no KeepAlive"
else
  PASS=$((PASS + 1))
  echo "PASS  LaunchAgent has no KeepAlive"
fi

if command grep -E '^[^#]*-extpass -[wsa]' "$OSX" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  -extpass -w/-s/-a is dash-duplicated; use -extpass=-w/-s/-a"
else
  PASS=$((PASS + 1))
  echo "PASS  -extpass uses equals form for -w/-s/-a"
fi

if ! command grep -F -- '-extpass=-w' "$OSX" >/dev/null ||
   ! command grep -F -- '-extpass=-s' "$OSX" >/dev/null ||
   ! command grep -F -- '-extpass=-a' "$OSX" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  mount passes -extpass=-w, -extpass=-s, and -extpass=-a"
else
  PASS=$((PASS + 1))
  echo "PASS  mount passes -extpass=-w, -extpass=-s, and -extpass=-a"
fi

if ! command grep -F 'find-generic-password -w' "$OSX" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  wait_for_keychain polls find-generic-password -w"
else
  PASS=$((PASS + 1))
  echo "PASS  wait_for_keychain polls find-generic-password -w"
fi

if ! command grep -F -- '-ko noappledouble,noapplexattr' "$OSX" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  mount passes -ko noappledouble,noapplexattr"
else
  PASS=$((PASS + 1))
  echo "PASS  mount passes -ko noappledouble,noapplexattr"
fi

if command grep -E -- '-ko local|,local' "$OSX" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  mount does not pass -ko local"
else
  PASS=$((PASS + 1))
  echo "PASS  mount does not pass -ko local"
fi

if command grep -F 'Dropbox/sync/sync_storage_private_docs.crypt' "$OSX" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  scripts do not mount the Dropbox cipherdir"
else
  PASS=$((PASS + 1))
  echo "PASS  scripts do not mount the Dropbox cipherdir"
fi

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
