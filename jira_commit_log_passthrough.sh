#!/bin/bash
# Passthrough: delegates to per-repo .git/hooks/<hook-name>
# Installed by jira_commit_log_setup.sh — do not edit ~/.githooks/_passthrough directly.
# Note: worktrees/submodules may not chain correctly (see setup script)
GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
GIT_DIR="$(cd "${GIT_DIR}" && pwd)"
LOCAL_HOOK="${GIT_DIR}/hooks/$(basename "$0")"
[ -x "${LOCAL_HOOK}" ] && exec "${LOCAL_HOOK}" "$@"
exit 0
