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

assert_match() {
    local label="$1" pattern="$2" haystack="$3"
    if echo "${haystack}" | command grep -qE "${pattern}"; then
        echo "  PASS: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label}"
        echo "    expected to match: ${pattern}"
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
assert_eq "raw has 7 TSV fields" "7" "${FIELD_COUNT}"

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
echo "=== Test 14: 7-field log format ==="
# Verify the log entries have 7 tab-separated fields
LOG_CONTENT="$(command cat "${LOG_FILE}")"
FIRST_LINE="$(echo "${LOG_CONTENT}" | command head -n 1)"
FIELD_COUNT="$(echo "${FIRST_LINE}" | command awk -F'\t' '{print NF}')"
assert_eq "log entry has 7 fields" "7" "${FIELD_COUNT}"
# Fields 5-7 should be numeric (files, insertions, deletions)
FIELD5="$(echo "${FIRST_LINE}" | command awk -F'\t' '{print $5}')"
FIELD6="$(echo "${FIRST_LINE}" | command awk -F'\t' '{print $6}')"
FIELD7="$(echo "${FIRST_LINE}" | command awk -F'\t' '{print $7}')"
assert_match "field 5 is numeric" '^[0-9]+$' "${FIELD5}"
assert_match "field 6 is numeric" '^[0-9]+$' "${FIELD6}"
assert_match "field 7 is numeric" '^[0-9]+$' "${FIELD7}"

echo ""
echo "=== Test 15: Time estimation in output ==="
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh")"
# Output should contain time estimates like "~0h 30m"
assert_match "output contains time estimate" '~[0-9]+h [0-9]+m' "${QUERY_OUTPUT}"
# Output should contain "Total:" line
assert_contains "output contains Total" "Total:" "${QUERY_OUTPUT}"

echo ""
echo "=== Test 16: Time estimation with known gaps (synthetic log) ==="
# Save current log, inject synthetic entries
command cp "${LOG_FILE}" "${LOG_FILE}.save14"
TODAY="$(date '+%Y-%m-%d')"
# Two commits 30 minutes apart in same repo, same ticket
printf '%sT10:00:00Z\tGAP-100\t/tmp/fakerepo\taaa1111\t5\t50\t10\n' "${TODAY}" > "${LOG_FILE}"
printf '%sT10:30:00Z\tGAP-100\t/tmp/fakerepo\tbbb2222\t3\t20\t5\n' "${TODAY}" >> "${LOG_FILE}"
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh" --date "${TODAY}")"
# First commit: new session = 30 + (50+10)/10 = 36 min
# Second commit: gap = 30 min (within 2h session)
# Total = 36 + 30 = 66 min = ~1h 06m
assert_contains "gap test shows GAP-100" "GAP-100" "${QUERY_OUTPUT}"
assert_match "gap test shows time" '~1h 06m' "${QUERY_OUTPUT}"
assert_contains "gap test shows 2 commits" "2 commits" "${QUERY_OUTPUT}"
command mv "${LOG_FILE}.save14" "${LOG_FILE}"

echo ""
echo "=== Test 17: Session gap handling (>2h gap) ==="
command cp "${LOG_FILE}" "${LOG_FILE}.save15"
TODAY="$(date '+%Y-%m-%d')"
# Two commits 3 hours apart — second should get new-session estimate
printf '%sT08:00:00Z\tSESS-200\t/tmp/fakerepo\taaa1111\t2\t30\t10\n' "${TODAY}" > "${LOG_FILE}"
printf '%sT11:00:00Z\tSESS-200\t/tmp/fakerepo\tbbb2222\t4\t100\t20\n' "${TODAY}" >> "${LOG_FILE}"
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh" --date "${TODAY}")"
# First: 30 + (30+10)/10 = 34 min
# Second: gap=3h>2h, so new session: 30 + (100+20)/10 = 42 min
# Total = 34 + 42 = 76 min = ~1h 16m
assert_contains "session gap shows SESS-200" "SESS-200" "${QUERY_OUTPUT}"
assert_match "session gap total time" '~1h 16m' "${QUERY_OUTPUT}"
command mv "${LOG_FILE}.save15" "${LOG_FILE}"

echo ""
echo "=== Test 18: Backward compat (mix of 4-field and 7-field entries) ==="
command cp "${LOG_FILE}" "${LOG_FILE}.save16"
TODAY="$(date '+%Y-%m-%d')"
# Old 4-field entry
printf '%sT09:00:00Z\tOLD-400\t/tmp/fakerepo\taaa1111\n' "${TODAY}" > "${LOG_FILE}"
# New 7-field entry
printf '%sT09:30:00Z\tNEW-700\t/tmp/fakerepo\tbbb2222\t3\t40\t10\n' "${TODAY}" >> "${LOG_FILE}"
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh" --date "${TODAY}")"
assert_contains "backward compat shows OLD-400" "OLD-400" "${QUERY_OUTPUT}"
assert_contains "backward compat shows NEW-700" "NEW-700" "${QUERY_OUTPUT}"
# OLD-400: new session, 0 diff lines => 30 + 0 = 30 min
assert_match "old entry gets 30m estimate" 'OLD-400.*~0h 30m' "${QUERY_OUTPUT}"
# Raw mode should output both as-is
RAW_OUTPUT="$("${DIR}/jira_commit_log.sh" --raw --date "${TODAY}")"
OLD_FIELDS="$(echo "${RAW_OUTPUT}" | command grep 'OLD-400' | command awk -F'\t' '{print NF}')"
NEW_FIELDS="$(echo "${RAW_OUTPUT}" | command grep 'NEW-700' | command awk -F'\t' '{print NF}')"
assert_eq "old entry has 4 raw fields" "4" "${OLD_FIELDS}"
assert_eq "new entry has 7 raw fields" "7" "${NEW_FIELDS}"
command mv "${LOG_FILE}.save16" "${LOG_FILE}"

echo ""
echo "=== Test 19: Commit with actual file changes (diff stats) ==="
# Remove local post-commit hook from test 12 to avoid interference
command rm -f .git/hooks/post-commit
: > "${LOG_FILE}"
echo "hello world" > "${TEST_REPO}/testfile.txt"
git add testfile.txt
git commit -q -m "DIFF-001 add test file"
LOG_CONTENT="$(command cat "${LOG_FILE}")"
DIFF_LINE="$(echo "${LOG_CONTENT}" | command grep 'DIFF-001')"
DIFF_FILES="$(echo "${DIFF_LINE}" | command awk -F'\t' '{print $5}')"
DIFF_INS="$(echo "${DIFF_LINE}" | command awk -F'\t' '{print $6}')"
DIFF_DEL="$(echo "${DIFF_LINE}" | command awk -F'\t' '{print $7}')"
assert_eq "diff stats: 1 file changed" "1" "${DIFF_FILES}"
assert_eq "diff stats: 1 insertion" "1" "${DIFF_INS}"
assert_eq "diff stats: 0 deletions" "0" "${DIFF_DEL}"

echo ""
echo "=== Test 20: Empty diff commit (no files changed) ==="
git commit -q --allow-empty -m "EMPTY-001 empty commit"
LOG_CONTENT="$(command cat "${LOG_FILE}")"
EMPTY_LINE="$(echo "${LOG_CONTENT}" | command grep 'EMPTY-001')"
EMPTY_FILES="$(echo "${EMPTY_LINE}" | command awk -F'\t' '{print $5}')"
EMPTY_INS="$(echo "${EMPTY_LINE}" | command awk -F'\t' '{print $6}')"
EMPTY_DEL="$(echo "${EMPTY_LINE}" | command awk -F'\t' '{print $7}')"
assert_eq "empty commit: 0 files" "0" "${EMPTY_FILES}"
assert_eq "empty commit: 0 insertions" "0" "${EMPTY_INS}"
assert_eq "empty commit: 0 deletions" "0" "${EMPTY_DEL}"

echo ""
echo "=== Test 21: Query output shows diff stats ==="
QUERY_OUTPUT="$("${DIR}/jira_commit_log.sh")"
# DIFF-001 should show +1/-0
assert_match "diff stats in output" 'DIFF-001.*\+1/-0' "${QUERY_OUTPUT}"

echo ""
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==============================="

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
