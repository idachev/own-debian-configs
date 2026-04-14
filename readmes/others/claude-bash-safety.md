# claude-bash-safety

A Claude Code `PreToolUse` hook that auto-approves obviously-safe read-only
Bash commands and asks for confirmation on anything mutating or ambiguous.
Ambiguous commands are classified by Haiku via a direct Anthropic API call.

## Files

| Path | Purpose |
|---|---|
| `~/bin/claude-bash-safety.sh` | The hook script (executed by Claude Code). |
| `~/bin/tests/claude-bash-safety/test_claude_bash_safety.sh` | Full test suite — always runs Haiku roundtrips. |
| `~/.claude/logs/bash-safety.log` | Decision audit log. |
| `~/.claude/settings.json` | Wires the hook into Claude Code (`PreToolUse` matcher `Bash`). |

## How it decides

The hook runs the following pipeline in order. First match wins.

1. **Non-Bash passthrough** — if `tool_name != "Bash"`, exits with empty
   stdout and lets Claude Code's default permission flow handle it. Runs
   before the recursion guard so Read/Edit/Write tool calls are never
   affected by a stale `CLAUDE_BASH_SAFETY_INFLIGHT` env var.

2. **Recursion guard** — if env var `CLAUDE_BASH_SAFETY_INFLIGHT=1` is set
   and we got this far (i.e. tool is Bash), returns `deny`. Fails closed
   to prevent loops and to harden against the env var being set in the
   outer shell.

3. **Fast denylist** — `/dev/null` redirects are stripped first (harmless,
   anchored so `/dev/null.bak` is NOT stripped), then the remaining command
   is grep'd against a set of "always unsafe regardless of flags"
   patterns: bare `rm`/`unlink`/`mv`/`cp`, any `ln` (symlink or hard
   link), `eval`/`exec`/`source`, POSIX dot-source at command start
   (`. foo`, `. ./foo`, `. /foo`), `sudo`, `git push --force`,
   `git reset --hard`, `git (commit|add|push|pull|merge|rebase|
   cherry-pick|tag|stash|branch -d)`, `curl | sh`, `date -s`/`--set`
   (system time, flag-specific), `mvn`/`gradle`/`./mvnw`/`./gradlew`
   (always executes project code), `make`, `env`/`printenv`/`set`/
   `export`/`unset` (env var readout/mutation), `ps e*` (BSD flag
   cluster leaks process env), `ssh`/`scp`/`rsync`/`nc`/`netcat`
   (remote execution and I/O), `tee` (writes files from stdin),
   `crontab`, `find ... -delete/-exec/-execdir/-ok/-okdir`
   (find-as-shell), `awk ... system(`/`awk ... | getline`/
   `awk ... print > file` (awk-as-shell), redirects to `/`, etc.
   On match returns `ask` — user can still approve case-by-case.
   Denylist is checked first, so `ls && rm -rf /tmp/foo` still
   escalates.

   **What's deliberately NOT on the denylist**: parameterized tools
   whose safety depends on verbs or flags — `gh`, `docker`, `kubectl`,
   `npm`/`yarn`/`pnpm`, `pip[23]?`, `apt`, `terraform`, `systemctl`,
   `journalctl`. These all route to the Haiku classifier, which sees
   the full command and won't go stale as those tools add new verbs.
   An earlier version enumerated unsafe `gh <verb>`s, but the list
   kept drifting; the current policy is "denylist = always unsafe,
   allowlist = known safe, Haiku = everything else".

4. **Compound detection** — if the command contains any of
   `| ; & \` $( < > (` or a literal newline, skip the fast allowlist and
   go straight to the classifier. This kills the whole class of
   "allowlisted prefix + `$(evil)`" bypasses — the allowlist only trusts
   truly simple commands.

5. **Tokenwise allowlist** (simple commands only) — the first whitespace
   token is compared byte-for-byte against an explicit bash array:
   `ls`, `cat`, `pwd`, `stat`, `file`, `tree`, `du`, `df`,
   `less`, `more`, `head`, `tail`, `wc`, `whoami`, `hostname`, `uname`,
   `uptime`, `date`, `id`, `type`, `which`, `grep`, `rg`, `fd`, `jq`,
   `yq`, `sort`, `uniq`, `cut`, `tr`, `basename`, `dirname`, `realpath`,
   `readlink`, etc. **`ps`, `find`, and `awk` are intentionally excluded**
   from the fast allowlist. `find` and `awk` can shell out
   (`find -delete`/`-exec`, `awk 'system(…)'`) in ways no regex on the
   outer command line will reliably catch. `ps` is excluded because the
   BSD `e` flag cluster (`ps e`, `ps auxe`) discloses process environment,
   leaking secrets like `ANTHROPIC_API_KEY`. All three instead roundtrip
   the Haiku classifier (~1s) for read-only invocations.

   **Tool-specific subcommand allowlists** apply after the tokenwise
   check for two tools that are used heavily enough to justify a fast
   path:

   - **`git`**: if the first token is `git`, the second token is checked
     against a read-only subcommand list (`status`, `log`, `diff`,
     `show`, `branch`, `remote`, `describe`, `rev-parse`, `ls-files`,
     `ls-tree`, `blame`, `reflog`, `shortlog`).
   - **`gh`** (GitHub CLI): safe-pattern allowlist in two shapes:
     - `ALLOW_GH_SINGLE` = `status version help search` — `gh <sub>`
       where args don't affect safety.
     - `ALLOW_GH_PAIRS` = `pr list|view|status|checks|diff`,
       `issue list|view|status`, `repo list|view`,
       `release list|view`, `run list|view|watch`,
       `workflow list|view`, `auth status`, `gist list|view`,
       `label list`, `alias list`, `extension list`.

     Policy: `gh` adds new unsafe verbs constantly (a moving target).
     Rather than chase them in the denylist, we assert what we know
     is read-only and route everything else (`gh pr create`,
     `gh api -X POST`, future verbs) to Haiku. `gh api /user` (a
     plain GET) routes through Haiku and is typically classified
     `SAFE`, while `gh api -X POST …` is classified `UNSAFE`.

   No regex prefix games, no word-boundary tricks — simple string
   equality. If matched, returns `allow` **with no LLM call** (fast,
   free).

6. **Haiku classifier** — the fallback for anything not caught by the
   fast paths. Builds a JSON request with `jq -n --arg` (safe from
   injection), POSTs to `https://api.anthropic.com/v1/messages` via
   `curl` with `max_tokens: 4` (hard cap against runaway output —
   the model physically cannot emit the full "Ignore previous
   instructions…" payload). Model: `claude-haiku-4-5` (floating alias).
   The verdict is normalized (whitespace + punctuation stripped,
   uppercased) and then **strict-matched** against `SAFE` or `UNSAFE`.
   Anything else — "not safe", "probably safe", truncated output,
   extra words — falls through to an unknown branch that returns
   `ask`. This replaces an older fuzzy `*SAFE*` wildcard that could
   mis-allow phrases like "NOT SAFE".
   On any error (missing API key, missing curl, timeout, HTTP non-zero,
   empty response, API error JSON, malformed content, unknown verdict)
   defaults to `ask`. Never fails open.

## Why simple-only allowlist?

Earlier versions had a pipeline-aware allowlist that split on `&& || ; |`
and checked each segment. That logic had two hard problems:

- **Command substitution bypass**: `ls $(evil_cmd)` looked like a safe
  `ls` command to the segment splitter, but the `$(...)` executes
  arbitrary code at full privilege.
- **Pipeline complexity**: every edge case in shell parsing (nested
  quotes, escaped semicolons, embedded newlines, backticks) was a
  potential bypass.

The compound-detection-plus-tokenwise approach trades ~1s of Haiku
latency on compound commands for much stronger safety of the fast path.
Simple commands (no shell specials, no pipes, no substitution) are the
only ones fast-allowed, and the allowlist check is a literal string
compare. Note however that tools whose *own* language can shell out
(awk `system()`, find `-exec/-delete`, anything with an eval-like
primitive) cannot be safely fast-allowed even as single tokens — those
are excluded from `ALLOW_TOKENS` and handled by the denylist plus the
Haiku roundtrip.

## Output format

Every decision is emitted on stdout as Claude Code's
[`hookSpecificOutput` JSON](https://code.claude.com/docs/en/hooks):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "ask" | "deny",
    "permissionDecisionReason": "..."
  }
}
```

Precedence in Claude Code when multiple hooks fire: `deny > defer > ask > allow`.

## Decisions in use

- `allow` — auto-approved, runs immediately, no prompt.
- `ask`   — Claude Code prompts the user (normal permission flow).
- `deny`  — blocked. Used only by the recursion guard; deny cannot be
  bypassed even with `--dangerously-skip-permissions`.

## Audit log

Every invocation appends one sanitized line to
`~/.claude/logs/bash-safety.log` (newlines in the command are stripped
to prevent log injection):

```
[2026-04-14 21:25:07] FAST-ALLOW: ls -la
[2026-04-14 21:25:07] DECISION=allow REASON=fast-allowlist (simple read-only command)
[2026-04-14 21:25:33] HAIKU-SAFE: curl -s https://api.github.com/repos/...
[2026-04-14 21:25:33] DECISION=allow REASON=Haiku classified as read-only
[2026-04-14 21:25:45] DENY-PATTERN matched '\brm\b' for: rm /tmp/foo
[2026-04-14 21:25:45] DECISION=ask REASON=matched risky pattern: \brm\b
```

Tail it while working to see what was auto-approved vs. escalated.

## Testing

```bash
# Full suite — 52 cases, always runs Haiku classifier roundtrips
~/bin/tests/claude-bash-safety/test_claude_bash_safety.sh
```

Requires `ANTHROPIC_API_KEY` in env. Every run exercises the Haiku
fallback so regressions in either the regex layer or the classifier
show up immediately.

Single manual test:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | ~/bin/claude-bash-safety.sh
```

## Installation

Add a `PreToolUse` entry matching `Bash` to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/bin/claude-bash-safety.sh",
            "timeout": 20
          }
        ]
      }
    ]
  }
}
```

Restart Claude Code (or start a new session) for the hook to take effect.

## Requirements

- `jq` (for JSON parsing)
- `curl` (for the Anthropic API call)
- `ANTHROPIC_API_KEY` in env (classifier uses the Anthropic REST API
  directly, not Claude Code subscription tokens — billing is separate)

## Tuning

- **Add to allowlist**: append a bare command name to `ALLOW_TOKENS` in
  `~/bin/claude-bash-safety.sh` for commands you want auto-approved
  without paying for a Haiku call. Only works for commands that are
  safe regardless of arguments — anything that touches env vars,
  writes files, or mutates state belongs in the denylist instead.
- **Add git subcommand**: append to `ALLOW_GIT_SUBCMDS`.
- **Add to denylist**: append to `DENY_PATTERNS` for patterns you want
  escalated to `ask` without a classifier roundtrip.
- **Change classifier**: `HAIKU_MODEL` and `HAIKU_TIMEOUT` at the top of
  the script.
- **Debug**: check `~/.claude/logs/bash-safety.log`.

## Caveats

- **Latency**: the Haiku fallback adds ~1s to every compound or unknown
  command (direct API call via curl). Simple whitelisted commands are
  instant. Denied commands are instant.
- **Token cost**: every classifier call spends ~100 input + 4 output
  tokens on Haiku (≈$0.0001 per call). Cheap, but non-zero over a long
  session.
- **Prompt injection**: the command text is fed to Haiku. A crafted
  command could try to manipulate the classifier. Defenses: the
  denylist is checked first; `max_tokens: 4` means the model cannot
  emit verbose injection payloads; verdict parsing is order-sensitive
  (`UNSAFE` beats `SAFE`). Still, for high-stakes environments, widen
  the denylist instead of trusting the classifier.
- **The classifier is advisory**: this hook trades off safety for
  convenience. Don't rely on it as your only guardrail — it's the first
  filter, not the last.
- **Billing**: direct API calls draw from your Anthropic API credit
  balance, not the Claude Code subscription. Calls are cheap but the
  balance is separate.
- **Model alias**: `claude-haiku-4-5` is a floating alias. Pin to
  `claude-haiku-4-5-20251001` in the script if you need reproducibility.
- Anthropic's own **Auto mode** (released March 2026) does something
  similar with a Sonnet 4.6 classifier built into Claude Code itself.
  Worth comparing before investing heavily in this hook.
