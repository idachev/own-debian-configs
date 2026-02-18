# Jira Commit Log

Tracks Jira ticket numbers from every local git commit via a global `post-commit` hook. Useful for reconstructing daily work when branches are squash-merged and individual commit history is lost.

## Scripts

| Script | Purpose |
|--------|---------|
| `jira_commit_log.sh` | Query logged tickets by date, project, etc. |
| `jira_commit_log_setup.sh` | One-time setup (installs hooks, sets git config) |
| `jira_commit_log_test.sh` | Automated test suite (22 tests) |

## Setup

Run once:

```bash
jira_commit_log_setup.sh
```

This will:
- Create `~/.githooks/` with a `post-commit` hook and passthrough hooks
- Set `git config --global core.hooksPath ~/.githooks`
- Create the log directory at `~/.local/share/jira-commit-log/`

If `core.hooksPath` is already set to a different path, the script will warn and exit. Use `--force` to override.

## How It Works

1. Every `git commit` triggers the global `post-commit` hook
2. The hook extracts Jira ticket IDs (pattern: `[A-Z]+-[0-9]+`) from the commit message
3. Each ticket is logged as a TSV line: `timestamp\tticket\trepo_path\tshort_hash`
4. The query script reads the log and groups tickets by date

### Passthrough Hooks

`core.hooksPath` completely replaces `.git/hooks/`. To preserve per-repo hooks (Husky, pre-commit framework, etc.), all other hook types are symlinked to a `_passthrough` script that delegates to the repo's `.git/hooks/<hook-name>`.

## Usage

```bash
# Today's tickets
jira_commit_log.sh

# Last 7 days
jira_commit_log.sh --days 7

# Specific date
jira_commit_log.sh --date 2026-02-13

# Filter by project
jira_commit_log.sh --days 30 --project LITE

# All tickets ever
jira_commit_log.sh --all

# Raw TSV output (for piping)
jira_commit_log.sh --raw
```

### Example Output

```
=== 2026-02-18 ===
  LITE-7260
  LITE-7261
  LITE-7280

=== 2026-02-17 ===
  LITE-7255
```

## Log Format

TSV file at `~/.local/share/jira-commit-log/commits.log`:

```
2026-02-18T10:30:45Z	LITE-7260	/home/user/repos/myproject	abc1234
```

Fields: UTC timestamp, ticket ID, repo path, short commit hash.

## Known Limitations

- **False positives:** The regex matches any `[A-Z]+-[0-9]+` pattern, so strings like `SHA-256` or `UTF-8` are logged. Use `--project` filter to narrow results.
- **Worktrees/submodules:** Ticket logging works, but local hook chaining may not (GIT_DIR resolves to `.git/worktrees/<name>/` instead of main `.git/`).
- **Tickets with `-000`** are excluded (e.g., `PROJ-000`), matching the convention in `github_utils.py`.

## Testing

```bash
jira_commit_log_test.sh
```

Runs 22 automated tests covering: single/multi-ticket logging, `-000` exclusion, false positives, passthrough hook chaining, query filters, raw output, and missing log file handling.

## Files

```
~/.githooks/
  post-commit          # Jira ticket logger + local hook chain
  _passthrough         # Universal passthrough (delegates to .git/hooks/)
  pre-commit -> _passthrough    # symlink
  commit-msg -> _passthrough    # symlink
  ... (16 symlinks total)

~/.local/share/jira-commit-log/
  commits.log          # Append-only TSV log (flock-protected)

~/bin/
  jira_commit_log.sh
  jira_commit_log_setup.sh
  jira_commit_log_test.sh
```
