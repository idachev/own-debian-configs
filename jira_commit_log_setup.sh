#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOOKS_DIR="${HOME}/.githooks"
LOG_DIR="${HOME}/.local/share/jira-commit-log"
FORCE=0

for arg in "$@"; do
    case "${arg}" in
        --force) FORCE=1 ;;
        --help|-h)
            echo "Usage: jira_commit_log_setup.sh [--force]"
            echo ""
            echo "Sets up global git hooks for Jira ticket tracking."
            echo "  --force  Overwrite existing core.hooksPath if set to a different path"
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            exit 1
            ;;
    esac
done

# --- Check existing core.hooksPath ---
EXISTING_HOOKS_PATH="$(git config --global core.hooksPath 2>/dev/null)"
if [ -n "${EXISTING_HOOKS_PATH}" ] && [ "${EXISTING_HOOKS_PATH}" != "${HOOKS_DIR}" ]; then
    echo "WARNING: core.hooksPath is already set to: ${EXISTING_HOOKS_PATH}"
    echo "This setup will change it to: ${HOOKS_DIR}"
    if [ "${FORCE}" -eq 0 ]; then
        echo "Use --force to overwrite, or manually reconcile."
        exit 1
    fi
    echo "Proceeding with --force..."
fi

# --- Create directories ---
mkdir -p "${HOOKS_DIR}"
mkdir -p "${LOG_DIR}"

# --- Write post-commit hook ---
cat > "${HOOKS_DIR}/post-commit" << 'HOOK_EOF'
#!/bin/bash
# Extract Jira tickets from commit message, log them, chain to local hook
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

LOG_DIR="${HOME}/.local/share/jira-commit-log"
LOG_FILE="${LOG_DIR}/commits.log"

TICKETS="$(printf '%s' "${COMMIT_MSG}" | grep -oE '[A-Z]+-[0-9]+' | grep -v -- '-000' | sort -u)"

if [ -n "${TICKETS}" ]; then
    mkdir -p "${LOG_DIR}" 2>/dev/null
    (
        flock -w 5 200 || { echo "warning: jira-commit-log: failed to acquire lock" >&2; exit 0; }
        WRITE_OK=1
        while IFS= read -r ticket; do
            if ! printf '%s\t%s\t%s\t%s\n' "${TIMESTAMP}" "${ticket}" "${REPO_ROOT}" "${COMMIT_HASH}" >> "${LOG_FILE}"; then
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
HOOK_EOF
chmod +x "${HOOKS_DIR}/post-commit"

# --- Write passthrough script ---
cat > "${HOOKS_DIR}/_passthrough" << 'HOOK_EOF'
#!/bin/bash
# Passthrough: delegates to per-repo .git/hooks/<hook-name>
# Note: worktrees/submodules may not chain correctly (see setup script)
GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
GIT_DIR="$(cd "${GIT_DIR}" && pwd)"
LOCAL_HOOK="${GIT_DIR}/hooks/$(basename "$0")"
[ -x "${LOCAL_HOOK}" ] && exec "${LOCAL_HOOK}" "$@"
exit 0
HOOK_EOF
chmod +x "${HOOKS_DIR}/_passthrough"

# --- Create symlinks for all other hook types ---
HOOK_TYPES=(
    pre-commit
    prepare-commit-msg
    commit-msg
    pre-merge-commit
    post-merge
    pre-rebase
    post-rewrite
    pre-push
    post-checkout
    post-update
    applypatch-msg
    pre-applypatch
    post-applypatch
    pre-auto-gc
    push-to-checkout
    sendemail-validate
)

for hook in "${HOOK_TYPES[@]}"; do
    ln -sf _passthrough "${HOOKS_DIR}/${hook}"
done

# --- Set global hooksPath ---
git config --global core.hooksPath "${HOOKS_DIR}"

# --- Summary ---
echo "Setup complete:"
echo "  Global hooks dir: ${HOOKS_DIR}"
echo "  Log directory:    ${LOG_DIR}"
echo "  core.hooksPath:   $(git config --global core.hooksPath)"
echo ""
echo "Hooks installed:"
echo "  post-commit   (Jira ticket logger + local hook chain)"
echo "  _passthrough  (delegates to per-repo hooks)"
echo "  ${#HOOK_TYPES[@]} symlinks -> _passthrough"
echo ""
echo "Test with: git commit --allow-empty -m 'TEST-001 verify hook'"
echo "Check log: cat ${LOG_DIR}/commits.log"
