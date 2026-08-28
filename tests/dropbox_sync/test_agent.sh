#!/bin/bash
# CLI contract for sync_laptop_osx_agent.sh.
# Does not bootstrap the LaunchAgent.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENT="${ROOT}/sync_laptop_osx_agent.sh"
SYNC_SCRIPT="$(command realpath "${HOME}/Dropbox/sync/sync_laptop_osx.sh")"

PASS=0
FAIL=0

assert_exit() {
  local name="$1"
  local expected="$2"
  shift 2
  local actual=0
  "$@" >/tmp/sync_laptop_osx_agent_out.txt 2>/tmp/sync_laptop_osx_agent_err.txt || actual=$?
  if [ "${actual}" -eq "${expected}" ]; then
    PASS=$((PASS + 1))
    echo "PASS  ${name}"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  ${name} (exit ${actual}, expected ${expected})"
    command cat /tmp/sync_laptop_osx_agent_out.txt /tmp/sync_laptop_osx_agent_err.txt
  fi
}

assert_stdout_grep() {
  local name="$1"
  local pattern="$2"
  shift 2
  if "$@" >/tmp/sync_laptop_osx_agent_out.txt 2>/tmp/sync_laptop_osx_agent_err.txt &&
    command grep -q "${pattern}" /tmp/sync_laptop_osx_agent_out.txt; then
    PASS=$((PASS + 1))
    echo "PASS  ${name}"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  ${name} (no match for /${pattern}/)"
    command cat /tmp/sync_laptop_osx_agent_out.txt /tmp/sync_laptop_osx_agent_err.txt
  fi
}

assert_exit_grep() {
  local name="$1"
  local expected="$2"
  local pattern="$3"
  shift 3
  local actual=0
  "$@" >/tmp/sync_laptop_osx_agent_out.txt 2>/tmp/sync_laptop_osx_agent_err.txt || actual=$?
  if [ "${actual}" -eq "${expected}" ] &&
    command grep -q "${pattern}" /tmp/sync_laptop_osx_agent_out.txt; then
    PASS=$((PASS + 1))
    echo "PASS  ${name}"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  ${name} (exit ${actual}, expected ${expected}, pattern /${pattern}/)"
    command cat /tmp/sync_laptop_osx_agent_out.txt /tmp/sync_laptop_osx_agent_err.txt
  fi
}

assert_plist_grep() {
  local name="$1"
  local pattern="$2"
  if command grep -q "${pattern}" /tmp/sync_laptop_osx_agent_plist.txt; then
    PASS=$((PASS + 1))
    echo "PASS  ${name}"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  ${name} (no match for /${pattern}/)"
    command cat /tmp/sync_laptop_osx_agent_plist.txt
  fi
}

assert_plist_no_grep() {
  local name="$1"
  local pattern="$2"
  if command grep -q "${pattern}" /tmp/sync_laptop_osx_agent_plist.txt; then
    FAIL=$((FAIL + 1))
    echo "FAIL  ${name} (matched /${pattern}/)"
    command cat /tmp/sync_laptop_osx_agent_plist.txt
  else
    PASS=$((PASS + 1))
    echo "PASS  ${name}"
  fi
}

echo "=== dropbox_sync LaunchAgent CLI ==="

if command bash -n "${AGENT}"; then
  PASS=$((PASS + 1))
  echo "PASS  bash -n"
else
  FAIL=$((FAIL + 1))
  echo "FAIL  bash -n"
fi

assert_exit "no args" 2 "${AGENT}"
assert_exit "bogus" 2 "${AGENT}" bogus
assert_exit "help" 0 "${AGENT}" --help
assert_stdout_grep "help names install" "sync_laptop_osx_agent.sh install" "${AGENT}" --help
assert_stdout_grep "help names uninstall" "uninstall" "${AGENT}" --help
assert_stdout_grep "help names status" "status" "${AGENT}" --help

assert_exit "print-plist" 0 "${AGENT}" print-plist
command cp /tmp/sync_laptop_osx_agent_out.txt /tmp/sync_laptop_osx_agent_plist.txt

assert_plist_grep "plist label" "com.idachev.sync-laptop-osx"
assert_plist_grep "plist runs doit" "doit"
assert_plist_grep "plist sync script" "${SYNC_SCRIPT}"
assert_plist_grep "plist homebrew PATH" "/opt/homebrew/bin"
assert_plist_grep "plist Aqua" "Aqua"
assert_plist_grep "plist minute 5" "<integer>5</integer>"
assert_plist_grep "plist hour 0" "<integer>0</integer>"
assert_plist_grep "plist hour 3" "<integer>3</integer>"
assert_plist_grep "plist hour 6" "<integer>6</integer>"
assert_plist_grep "plist hour 9" "<integer>9</integer>"
assert_plist_grep "plist hour 12" "<integer>12</integer>"
assert_plist_grep "plist hour 15" "<integer>15</integer>"
assert_plist_grep "plist hour 18" "<integer>18</integer>"
assert_plist_grep "plist hour 21" "<integer>21</integer>"
assert_plist_no_grep "plist has no KeepAlive" "KeepAlive"
assert_plist_no_grep "plist has no RunAtLoad" "RunAtLoad"

if command grep -E 'sudo launchctl (load|unload)' "${AGENT}" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "FAIL  scripts have no sudo load/unload"
else
  PASS=$((PASS + 1))
  echo "PASS  scripts have no sudo load/unload"
fi

assert_exit "status missing agent" 1 env \
  AGENT_LABEL=com.idachev.test.sync-laptop-osx.missing \
  AGENT_PLIST=/tmp/sync-laptop-osx-missing.plist \
  "${AGENT}" status

command awk '
  /<string>Aqua<\/string>/ {
    print
    print "  <key>RunAtLoad</key>"
    print "  <true/>"
    next
  }
  { print }
' /tmp/sync_laptop_osx_agent_plist.txt >/tmp/sync_laptop_osx_agent_runatload.plist

assert_exit_grep "status rejects RunAtLoad" 1 "runatload: present" env \
  AGENT_LABEL=com.idachev.test.sync-laptop-osx.runatload \
  AGENT_PLIST=/tmp/sync_laptop_osx_agent_runatload.plist \
  "${AGENT}" status

echo
echo "pass=${PASS} fail=${FAIL}"
[ "${FAIL}" -eq 0 ]
