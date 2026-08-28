#!/bin/bash
# CLI contract for anydesk_ctl.sh and teamviewer_ctl.sh.
# Does not start or stop TeamViewer (needs sudo and changes daemons).

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANYDESK="${ROOT}/anydesk_ctl.sh"
TEAMVIEWER="${ROOT}/teamviewer_ctl.sh"

PASS=0
FAIL=0

assert_exit() {
  local name="$1"
  local expected="$2"
  shift 2
  local actual=0
  "$@" >/tmp/remote_ctl_out.txt 2>/tmp/remote_ctl_err.txt || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1))
    echo "PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $name (exit $actual, expected $expected)"
    command cat /tmp/remote_ctl_err.txt
  fi
}

assert_stdout_grep() {
  local name="$1"
  local pattern="$2"
  shift 2
  if "$@" >/tmp/remote_ctl_out.txt 2>/tmp/remote_ctl_err.txt &&
    command grep -q "$pattern" /tmp/remote_ctl_out.txt; then
    PASS=$((PASS + 1))
    echo "PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $name (no match for /$pattern/)"
    command cat /tmp/remote_ctl_out.txt /tmp/remote_ctl_err.txt
  fi
}

echo "=== remote_ctl CLI ==="

assert_exit "anydesk no args" 2 "$ANYDESK"
assert_exit "teamviewer no args" 2 "$TEAMVIEWER"
assert_exit "anydesk bogus" 2 "$ANYDESK" bogus
assert_exit "anydesk help" 0 "$ANYDESK" --help
assert_exit "teamviewer help" 0 "$TEAMVIEWER" --help
assert_stdout_grep "anydesk help text" "anydesk_ctl.sh" "$ANYDESK" --help
assert_stdout_grep "teamviewer help text" "teamviewer_ctl.sh" "$TEAMVIEWER" --help
assert_exit "anydesk status" 0 "$ANYDESK" status
assert_stdout_grep "anydesk status names app" "AnyDesk" "$ANYDESK" status
assert_exit "teamviewer status" 0 "$TEAMVIEWER" status
assert_stdout_grep "teamviewer status names app" "TeamViewer" "$TEAMVIEWER" status
assert_exit "anydesk stop when idle" 0 "$ANYDESK" stop

if command grep -E 'sudo launchctl (load|unload)' "$TEAMVIEWER" "$ANYDESK" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  ctl scripts have no sudo load/unload (LaunchAgents as root warns)"
else
  PASS=$((PASS + 1))
  echo "PASS  ctl scripts have no sudo load/unload"
fi

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
