#!/bin/bash
# Global post-commit hook: extract Jira tickets from commit message and log them.
# Installed by jira_commit_log_setup.sh — do not edit ~/.githooks/post-commit directly.
#
# Ticket regex: [A-Z]+-[0-9]+ — canonical source: github_utils.py:248
# Known false positives: SHA-256, UTF-8, etc. Accepted trade-off;
# use --project filter in query script to narrow results.
#
# Worktrees/submodules: local hook chaining may not work (GIT_DIR
# resolves to .git/worktrees/<name>/ instead of main .git/).

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
GIT_DIR="$(cd "${GIT_DIR}" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || dirname "${GIT_DIR}")"
COMMIT_HASH="$(git rev-parse --short HEAD 2>/dev/null)"
COMMIT_MSG="$(git log -1 --pretty=%B 2>/dev/null)"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# --- Diff stats ---
PARENT_COUNT="$(git log --format='%P' -1 | wc -w)"
if [ "${PARENT_COUNT}" -eq 0 ]; then
    DIFF_STAT="$(git diff-tree --root --shortstat HEAD 2>/dev/null | command tail -n 1)"
else
    DIFF_STAT="$(git diff --shortstat HEAD~1..HEAD 2>/dev/null)"
fi
FILES_CHANGED="$(echo "${DIFF_STAT}" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+')"
INSERTIONS="$(echo "${DIFF_STAT}" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')"
DELETIONS="$(echo "${DIFF_STAT}" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')"
FILES_CHANGED="${FILES_CHANGED:-0}"
INSERTIONS="${INSERTIONS:-0}"
DELETIONS="${DELETIONS:-0}"

LOG_DIR="${HOME}/.local/share/jira-commit-log"
LOG_FILE="${LOG_DIR}/commits.log"

TICKETS="$(printf '%s' "${COMMIT_MSG}" | grep -oE '[A-Z]+-[0-9]+' | grep -v -- '-000' | sort -u)"

if [ -n "${TICKETS}" ]; then
    mkdir -p "${LOG_DIR}" 2>/dev/null
    (
        flock -w 5 200 || { echo "warning: jira-commit-log: failed to acquire lock" >&2; exit 0; }
        WRITE_OK=1
        while IFS= read -r ticket; do
            if ! printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${TIMESTAMP}" "${ticket}" "${REPO_ROOT}" "${COMMIT_HASH}" \
                "${FILES_CHANGED}" "${INSERTIONS}" "${DELETIONS}" >> "${LOG_FILE}"; then
                WRITE_OK=0
            fi
        done <<< "${TICKETS}"
        if [ "${WRITE_OK}" -eq 0 ]; then
            echo "warning: jira-commit-log: failed to write to ${LOG_FILE}" >&2
        fi
    ) 200>"${LOG_FILE}.lock"
fi

# Chain to per-repo hook
LOCAL_HOOK="${GIT_DIR}/hooks/post-commit"
[ -x "${LOCAL_HOOK}" ] && exec "${LOCAL_HOOK}" "$@"
exit 0
