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

3. **Fast denylist** — `/dev/null` redirects are stripped first (harmless),
   then the remaining command is grep'd against a set of dangerous regex
   patterns: bare `rm`/`mv`/`cp`, `eval`/`exec`/`source`, POSIX dot-source
   at command start (`. foo`, `. ./foo`, `. /foo`), `sudo`,
   `git push --force`, `git reset --hard`, `curl | sh`, `npm install`,
   `docker run`, `kubectl apply`, `mvn`, `./gradlew`,
   `env`/`printenv`/`set`/`export`/`unset` (env var readout/mutation),
   `ssh`/`scp`/`rsync`/`nc`/`netcat` (remote execution and I/O),
   `tee` (writes files from stdin), `crontab`/`systemctl`/`journalctl`,
   `find ... -delete`/`-exec`/`-execdir`/`-ok`/`-okdir` (find-as-shell),
   `awk ... system(`/`awk ... | getline`/`awk ... print > file`
   (awk-as-shell), redirects to `/`, etc. On match returns `ask` — user
   can still approve case-by-case. Denylist is checked first, so
   `ls && rm -rf /tmp/foo` still escalates.

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
   `yq`, `sort`, `uniq`, `cut`, `tr`, `basename`, `dirname`, `ps`, etc.
   **`find` and `awk` are intentionally excluded** from the fast allowlist
   because they can shell out (`find -delete`/`-exec`, `awk 'system(…)'`)
   in ways no regex on the outer command line will reliably catch.
   Read-only `find`/`awk` invocations instead roundtrip the Haiku
   classifier (~1s). If the first token is `git`, the second token is
   checked against a list of read-only subcommands (`status`, `log`,
   `diff`, `show`, `branch`, `remote`, `describe`, `rev-parse`,
   `ls-files`, `ls-tree`, `blame`, `reflog`, `shortlog`). No regex prefix
   games, no word-boundary tricks — simple string equality.
   If matched, returns `allow` **with no LLM call** (fast, free).

6. **Haiku classifier** — the fallback for anything not caught by the
   fast paths. Builds a JSON request with `jq -n --arg` (safe from
   injection), POSTs to `https://api.anthropic.com/v1/messages` via
   `curl` with `max_tokens: 4` (hard cap against runaway output —
   the model physically cannot emit the full "Ignore previous
   instructions…" payload). Model: `claude-haiku-4-5` (floating alias).
   Classifies as `SAFE` or `UNSAFE`; verdict case-statement checks
   `*UNSAFE*` before `*SAFE*` so a verbose "SAFE but actually UNSAFE"
   still resolves to UNSAFE.
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
