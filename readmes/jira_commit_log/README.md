# Jira Commit Log

Tracks Jira ticket numbers from every local git commit via a global `post-commit` hook. Useful for reconstructing daily work when branches are squash-merged and individual commit history is lost.

## Scripts

| Script | Purpose |
|--------|---------|
| `jira_commit_log.sh` | Query logged tickets by date, project, etc. |
| `jira_commit_log_setup.sh` | One-time setup (installs hooks, sets git config) |
| `jira_commit_log_test.sh` | Automated test suite |
| `jira_commit_log_hook.sh` | Post-commit hook source (copied to ~/.githooks/ by setup) |
| `jira_commit_log_passthrough.sh` | Passthrough hook source (copied to ~/.githooks/ by setup) |

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
3. Diff stats (files changed, insertions, deletions) are captured via `git diff --shortstat`
4. Each ticket is logged as a 7-field TSV line (see Log Format below)
5. The query script reads the log, estimates work time, and groups tickets by date

### Time Estimation Algorithm

For each `(date, ticket)` pair, the query script estimates work time:

1. Collects all commits for that ticket on that date, ordered by timestamp
2. For each commit, computes gap to previous commit **in the same repo**
3. If gap > 2 hours OR first commit: estimate = 30 min + 1 min per 10 lines changed
4. If gap <= 2 hours: estimate = gap duration
5. Sums estimates per ticket per day

### Passthrough Hooks

`core.hooksPath` completely replaces `.git/hooks/`. To preserve per-repo hooks (Husky, pre-commit framework, etc.), all other hook types are symlinked to a `_passthrough` script that delegates to the repo's `.git/hooks/<hook-name>`.

## Usage

```bash
# Today's tickets with time estimates
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
  LITE-7260      ~1h 30m  (3 commits, +245/-30)
  LITE-7261      ~0h 45m  (1 commit, +42/-15)
  ---
  Total:         ~2h 15m

=== 2026-02-17 ===
  LITE-7255      ~0h 30m  (1 commit, +12/-3)
  ---
  Total:         ~0h 30m
```

## Log Format

TSV file at `~/.local/share/jira-commit-log/commits.log`:

```
2026-02-18T10:30:45Z	LITE-7260	/home/user/repos/myproject	abc1234	5	120	30
```

7 fields: UTC timestamp, ticket ID, repo path, short commit hash, files changed, insertions, deletions.

Old 4-field entries (from before this update) are supported — missing fields default to 0.

## Known Limitations

- **False positives:** The regex matches any `[A-Z]+-[0-9]+` pattern, so strings like `SHA-256` or `UTF-8` are logged. Use `--project` filter to narrow results.
- **Worktrees/submodules:** Ticket logging works, but local hook chaining may not (GIT_DIR resolves to `.git/worktrees/<name>/` instead of main `.git/`).
- **Tickets with `-000`** are excluded (e.g., `PROJ-000`), matching the convention in `github_utils.py`.
- **Time estimates are approximate.** They use inter-commit timing and diff size heuristics. Actual time may vary.

## Testing

```bash
jira_commit_log_test.sh
```

Runs automated tests covering: single/multi-ticket logging, `-000` exclusion, false positives, passthrough hook chaining, query filters, raw output, missing log file handling, 7-field format, diff stats, time estimation, session gaps, and backward compatibility.

## Files

```
~/bin/
  jira_commit_log.sh              # Query script
  jira_commit_log_setup.sh        # Setup script (copies hooks)
  jira_commit_log_test.sh         # Test suite
  jira_commit_log_hook.sh         # Post-commit hook source
  jira_commit_log_passthrough.sh  # Passthrough hook source

~/.githooks/
  post-commit          # Copied from jira_commit_log_hook.sh
  _passthrough         # Copied from jira_commit_log_passthrough.sh
  pre-commit -> _passthrough    # symlink
  commit-msg -> _passthrough    # symlink
  ... (16 symlinks total)

~/.local/share/jira-commit-log/
  commits.log          # Append-only 7-field TSV log (flock-protected)
```
