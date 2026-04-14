# claude-bash-safety

A Claude Code `PreToolUse` hook that auto-approves obviously-safe
read-only Bash commands and asks for confirmation on anything mutating
or ambiguous. Ambiguous commands are classified by Haiku via a direct
Anthropic API call.

## Files

| Path | Purpose |
|---|---|
| `~/bin/claude-bash-safety.sh` | The hook script (executed by Claude Code). |
| `~/bin/tests/claude-bash-safety/test_claude_bash_safety.sh` | End-to-end test suite. Always runs Haiku roundtrips. |
| `~/.claude/logs/bash-safety.log` | Decision audit log. |
| `~/.claude/settings.json` | Wires the hook into Claude Code (`PreToolUse` matcher `Bash`). |

## How it decides

First match wins. The exact patterns, token sets, and subcommand lists
live in `claude-bash-safety.sh` — read the source for specifics.

1. **Non-Bash passthrough** — non-Bash tool calls exit with empty stdout
   so Claude Code's default permission flow handles them. Runs before
   the recursion guard so Read/Edit/Write are never affected.

2. **Recursion guard** — if `CLAUDE_BASH_SAFETY_INFLIGHT=1` is set in
   the environment, returns `deny`. Nothing in the hook sets this
   variable itself (the classifier is a plain `curl`, not a Bash
   subprocess), so the guard only fires on outer-shell env pollution.
   `deny` cannot be bypassed even with `--dangerously-skip-permissions`.

3. **Fast denylist** — `/dev/null` redirects are stripped first
   (anchored so `/dev/null.bak` is NOT stripped), then the remaining
   command is grep'd against "always unsafe regardless of flags" regex
   patterns. On match returns `ask` (not `deny`) so the user can still
   approve case-by-case. Denylist runs before compound detection, so
   `ls && rm -rf /tmp/foo` still escalates.

   **Deliberately NOT on the denylist**: parameterized tools whose
   safety depends on verbs or flags — `gh`, `docker`, `kubectl`,
   `npm`/`yarn`/`pnpm`, `pip`, `apt`, `terraform`, `systemctl`, `ps`.
   These route to the Haiku classifier, which sees the full command
   and won't go stale as those tools add new verbs.

4. **Compound detection** — if the command contains any of
   `` | ; & ` $( < > ( `` or a literal newline, skip the fast allowlist
   and go straight to the classifier. This kills the whole class of
   "allowlisted prefix + `$(evil)`" bypasses.

5. **Tokenwise allowlist** (simple commands only) — the first whitespace
   token is compared byte-for-byte against an explicit bash array. No
   regex prefix games, no word-boundary tricks. Tool-specific subcommand
   allowlists apply for `git` (read-only subcommands, including
   `stash list`/`stash show`) and `gh` (read-only single verbs and
   `<sub> <action>` pairs). Matched commands return `allow` **with no
   LLM call** (fast, free).

6. **Haiku classifier** — the fallback for anything not caught above.
   Builds a JSON request with `jq -n --arg` (injection-safe), POSTs to
   the Anthropic API with `max_tokens: 4` (hard cap — the model
   physically cannot emit a long injection payload). Verdict is
   normalized and strict-matched against `SAFE` or `UNSAFE`; anything
   else falls through to `ask`. On any error (missing key, timeout,
   empty response, API error, unknown verdict) defaults to `ask`.
   Never fails open.

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

Precedence when multiple hooks fire: `deny > defer > ask > allow`.

- `allow` — auto-approved, runs immediately, no prompt.
- `ask`   — Claude Code prompts the user (normal permission flow).
- `deny`  — blocked. Used only by the recursion guard.

## Audit log

Every invocation appends one sanitized line to
`~/.claude/logs/bash-safety.log` (newlines are stripped to prevent log
injection). Tail it while working to see what was auto-approved vs.
escalated.

## Testing

```bash
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

- `jq` (JSON parsing)
- `curl` (Anthropic API call)
- `ANTHROPIC_API_KEY` in env — classifier uses the Anthropic REST API
  directly, not Claude Code subscription tokens. Billing is separate.

## Caveats

- **Latency**: Haiku fallback adds ~1s to every compound or unknown
  command. Fast-allowed and denied commands are instant.
- **Token cost**: ~100 input + 4 output tokens per classifier call
  (≈$0.0001). Cheap, but non-zero over a long session.
- **Prompt injection**: the command text is fed to Haiku. Defenses —
  denylist is checked first, `max_tokens: 4` bounds the output, verdict
  parsing is strict-match. For high-stakes environments, widen the
  denylist instead of trusting the classifier.
- **Advisory, not authoritative**: this hook trades safety for
  convenience. It's the first filter, not the last.
