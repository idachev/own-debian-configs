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

# --- Install post-commit hook (from separate source file) ---
command cp "${DIR}/jira_commit_log_hook.sh" "${HOOKS_DIR}/post-commit"
chmod +x "${HOOKS_DIR}/post-commit"

# --- Install passthrough script (from separate source file) ---
command cp "${DIR}/jira_commit_log_passthrough.sh" "${HOOKS_DIR}/_passthrough"
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
