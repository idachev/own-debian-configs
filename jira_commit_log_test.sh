#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Self-contained test for jira_commit_log system.
# Creates a temp repo, runs test scenarios, asserts results, cleans up.
# Safe to run anytime — does not modify real log or repos.

set -euo pipefail

PASS=0
FAIL=0
LOG_FILE="${HOME}/.local/share/jira-commit-log/commits.log"
BACKUP_LOG=""

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "${expected}" = "${actual}" ]; then
        echo "  PASS: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label}"
        echo "    expected: ${expected}"
        echo "    actual:   ${actual}"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "${haystack}" | command grep -qF "${needle}"; then
        echo "  PASS: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label}"
        echo "    expected to contain: ${needle}"
        echo "    actual: ${haystack}"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if ! echo "${haystack}" | command grep -qF "${needle}"; then
        echo "  PASS: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label}"
        echo "    expected NOT to contain: ${needle}"
        echo "    actual: ${haystack}"
        FAIL=$((FAIL + 1))
    fi
}

cleanup() {
    # Restore original log if backed up
    if [ -n "${BACKUP_LOG}" ] && [ -f "${BACKUP_LOG}" ]; then
        command mv "${BACKUP_LOG}" "${LOG_FILE}"
    elif [ -n "${BACKUP_LOG}" ]; then
        # No backup existed, remove test log
        command rm -f "${LOG_FILE}" "${LOG_FILE}.lock"
    fi
    # Remove temp repo
    if [ -n "${TEST_REPO:-}" ] && [ -d "${TEST_REPO}" ]; then
        command rm -rf "${TEST_REPO}"
    fi
}
trap cleanup EXIT

# --- Backup existing log ---
if [ -f "${LOG_FILE}" ]; then
    BACKUP_LOG="${LOG_FILE}.test-backup.$$"
    command cp "${LOG_FILE}" "${BACKUP_LOG}"
    : > "${LOG_FILE}"
else
    BACKUP_LOG="${LOG_FILE}.test-backup.$$"
    # Mark that no original existed
fi

# --- Verify prerequisites ---
HOOKS_PATH="$(git config --global core.hooksPath 2>/dev/null || true)"
if [ "${HOOKS_PATH}" != "${HOME}/.githooks" ]; then
    echo "ERROR: core.hooksPath is not set to ~/.githooks (got: '${HOOKS_PATH}')"
    echo "Run jira_commit_log_setup.sh first."
    exit 1
fi

# --- Create temp repo ---
TEST_REPO="$(mktemp -d)"
cd "${TEST_REPO}"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
git commit -q --allow-empty -m "initial commit (no ticket)"

echo ""
echo "=== Test 1: Single ticket ==="
git commit -q --allow-empty -m "TEST-001 single ticket test"
LOG_CONTENT="$(command cat "${LOG_FILE}")"
assert_contains "TEST-001 in log" "TEST-001" "${LOG_CONTENT}"
LINES="$(echo "${LOG_CONTENT}" | command wc -l | tr -d ' ')"
assert_eq "exactly 1 log line" "1" "${LINES}"

echo ""
echo "=== Test 2: Multi-ticket ==="
git commit -q --allow-empty -m "PROJ-123 TEAM-456 fix and refactor"
LOG_CONTENT="$(command cat "${LOG_FILE}")"
assert_contains "PROJ-123 in log" "PROJ-123" "${LOG_CONTENT}"
assert_contains "TEAM-456 in log" "TEAM-456" "${LOG_CONTENT}"
LINES="$(echo "${LOG_CONTENT}" | command wc -l | tr -d ' ')"
assert_eq "exactly 3 log lines" "3" "${LINES}"

echo ""
echo "=== Test 3: No ticket (should not add lines) ==="
git commit -q --allow-empty -m "no ticket in this message"
LOG_CONTENT="$(command cat "${LOG_FILE}")"
LINES="$(echo "${LOG_CONTENT}" | command wc -l | tr -d ' ')"
assert_eq "still 3 log lines" "3" "${LINES}"

echo ""
echo "=== Test 4: -000 exclusion ==="
git commit -q --allow-empty -m "SKIP-000 should be excluded"
LOG_CONTENT="$(command cat "${LOG_FILE}")"
assert_not_contains "SKIP-000 excluded" "SKIP-000" "${LOG_CONTENT}"
LINES="$(echo "${LOG_CONTENT}" | command wc -l | tr -d ' ')"
assert_eq "still 3 log lines" "3" "${LINES}"

echo ""
echo "=== Test 5: False positive (SHA-256) ==="
git commit -q --allow-empty -m "Update SHA-256 hashing algorithm"
LOG_CONTENT="$(command cat "${LOG_FILE}")"
assert_contains "SHA-256 in log (known false positive)" "SHA-256" "${LOG_CONTENT}"

echo ""
echo "=== Test 6: Query script - default (today) ==="
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh")"
assert_contains "query shows TEST-001" "TEST-001" "${QUERY_OUTPUT}"
assert_contains "query shows PROJ-123" "PROJ-123" "${QUERY_OUTPUT}"
assert_contains "query shows TEAM-456" "TEAM-456" "${QUERY_OUTPUT}"

echo ""
echo "=== Test 7: Query script - project filter ==="
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh" --project TEST)"
assert_contains "filter shows TEST-001" "TEST-001" "${QUERY_OUTPUT}"
assert_not_contains "filter excludes PROJ-123" "PROJ-123" "${QUERY_OUTPUT}"
assert_not_contains "filter excludes TEAM-456" "TEAM-456" "${QUERY_OUTPUT}"

echo ""
echo "=== Test 8: Query script - raw mode ==="
RAW_OUTPUT="$("${DIR}/jira_commit_log.sh" --raw)"
# Raw should have tab-separated fields
FIRST_LINE="$(echo "${RAW_OUTPUT}" | command head -n 1)"
FIELD_COUNT="$(echo "${FIRST_LINE}" | command awk -F'\t' '{print NF}')"
assert_eq "raw has 4 TSV fields" "4" "${FIELD_COUNT}"

echo ""
echo "=== Test 9: Query script - date filter ==="
TODAY="$(date '+%Y-%m-%d')"
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh" --date "${TODAY}")"
assert_contains "date filter shows today's tickets" "TEST-001" "${QUERY_OUTPUT}"

echo ""
echo "=== Test 10: Query script - days filter ==="
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh" --days 1)"
assert_contains "days filter shows recent tickets" "TEST-001" "${QUERY_OUTPUT}"

echo ""
echo "=== Test 11: Passthrough - pre-commit hook ==="
MARKER_FILE="${TEST_REPO}/pre-commit-marker"
mkdir -p .git/hooks
printf '#!/bin/bash\ntouch "%s"\n' "${MARKER_FILE}" > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git commit -q --allow-empty -m "TEST-010 passthrough test"
if [ -f "${MARKER_FILE}" ]; then
    echo "  PASS: pre-commit passthrough works"
    PASS=$((PASS + 1))
else
    echo "  FAIL: pre-commit passthrough did not fire"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Test 12: Passthrough - post-commit chain ==="
POST_MARKER="${TEST_REPO}/post-commit-marker"
printf '#!/bin/bash\ntouch "%s"\n' "${POST_MARKER}" > .git/hooks/post-commit
chmod +x .git/hooks/post-commit
git commit -q --allow-empty -m "TEST-011 post-commit chain test"
if [ -f "${POST_MARKER}" ]; then
    echo "  PASS: post-commit chain works"
    PASS=$((PASS + 1))
else
    echo "  FAIL: post-commit chain did not fire"
    FAIL=$((FAIL + 1))
fi
# Also verify ticket was logged (both logging AND chaining work)
LOG_CONTENT="$(command cat "${LOG_FILE}")"
assert_contains "TEST-011 logged despite chain" "TEST-011" "${LOG_CONTENT}"

echo ""
echo "=== Test 13: Query script - no log file ==="
command mv "${LOG_FILE}" "${LOG_FILE}.tmp"
NO_LOG_OUTPUT="$("${DIR}/jira_commit_log.sh" 2>&1)"
assert_contains "missing log message" "No commit log found" "${NO_LOG_OUTPUT}"
command mv "${LOG_FILE}.tmp" "${LOG_FILE}"

echo ""
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==============================="

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
