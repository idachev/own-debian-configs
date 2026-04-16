#!/bin/bash
# Claude Code PreToolUse hook: auto-approve safe read-only Bash commands
#
# Reads PreToolUse JSON from stdin. For Bash tool calls, decides:
#   - allow:       command is clearly safe / read-only
#   - passthrough: fall through to Claude Code's built-in permission checks
#   - deny:        recursion guard tripped
# Decision is emitted on stdout as hookSpecificOutput JSON.
# Passthrough emits NO JSON — Claude Code sees no hook output and applies
# its own allow/ask/deny logic as if this hook didn't exist.
#
# Flow:
#   1. Non-Bash tool calls pass through untouched
#   2. Recursion guard (fails closed with deny)
#   3. Fast denylist of obviously dangerous patterns - passthrough to
#      Claude Code's built-in permission checks
#   4. If command contains any compound/redirect/substitution characters
#      (| ; & ` $( < >  newline), skip the allowlist and go straight
#      to the Haiku classifier. The allowlist is too easy to fool in
#      compound commands, so we pay the ~1s classifier latency.
#   5. Simple single-token command: tokenwise allowlist match -> allow
#   6. Fall back to Haiku classifier via direct Anthropic API
#
# On any error, defaults to passthrough (fail-safe to Claude Code's
# built-in checks).
#
# Test manually:
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | \
#     ~/bin/claude-bash-safety.sh

set -u -o pipefail

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/bash-safety.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

HAIKU_MODEL="claude-haiku-4-5"
HAIKU_TIMEOUT=10
ANTHROPIC_API_URL="https://api.anthropic.com/v1/messages"

# Log a sanitized message. Strips newlines/CR to prevent log injection
# via a command that contains embedded line breaks.
log() {
  local ts msg
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  msg=$(printf '%s' "$*" | tr '\n\r' '  ')
  printf '[%s] %s\n' "$ts" "$msg" >>"$LOG_FILE" 2>/dev/null || true
}

emit_decision() {
  local decision="$1"
  local reason="$2"
  log "DECISION=$decision REASON=$reason"
  jq -n \
    --arg d "$decision" \
    --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# Fall through to Claude Code's built-in permission checks.
# Emits no JSON so the hook is invisible to the decision engine —
# Claude Code then applies its own allow/ask/deny logic as if this
# hook didn't exist.
passthrough() {
  local reason="$1"
  log "PASSTHROUGH REASON=$reason"
  exit 0
}

# ---- Parse stdin -----------------------------------------------------------
INPUT=$(cat)
if [ -z "$INPUT" ]; then
  log "ERROR empty stdin"
  passthrough "empty hook input"
fi

if ! command -v jq >/dev/null 2>&1; then
  log "ERROR jq not installed"
  passthrough "jq not installed on host"
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Non-Bash tool calls: emit nothing, let Claude Code's default flow handle them.
# This check runs BEFORE the recursion guard so Read/Edit/Write etc. are never
# affected by a stale CLAUDE_BASH_SAFETY_INFLIGHT env var.
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# ---- Recursion guard -------------------------------------------------------
# Outer-shell hardening: nothing in this hook actually sets
# CLAUDE_BASH_SAFETY_INFLIGHT — the classifier runs via curl, not Bash —
# so this guard only fires when the variable is set externally (accidental
# export in the outer shell, a misconfigured test fixture, a wrapper script
# that leaks env). Fail closed with deny because deny cannot be bypassed
# even with --dangerously-skip-permissions, making it the strongest response
# available when the environment already looks compromised.
if [ "${CLAUDE_BASH_SAFETY_INFLIGHT:-0}" = "1" ]; then
  emit_decision "deny" "CLAUDE_BASH_SAFETY_INFLIGHT set in outer shell"
fi

if [ -z "$CMD" ]; then
  log "ERROR bash tool call with empty command"
  passthrough "empty command"
fi

# ---- Fast denylist ---------------------------------------------------------
# Policy: this list enumerates commands that are ALWAYS unsafe regardless
# of flags or subcommands. Parameterized tools (gh, docker, kubectl, npm,
# yarn, pnpm, pip, apt, terraform, systemctl, journalctl, …) are
# deliberately NOT listed — they route to the Haiku classifier, which sees
# the full command and won't go stale as those tools add new verbs. For
# `git` and `gh` we keep a narrower pattern: `git` has a stable mutation
# verb set (and it's hot enough that the fast path is worth it), and `gh`
# has a small "known-safe" allowlist (ALLOW_GH_*) defined below. Match
# anywhere in the command, so `ls && rm -rf /tmp/foo` still escalates.
# Returns "ask" (not "deny") so the user can still approve case-by-case.
DENY_PATTERNS=(
  '\brm\b'                                  # any rm - too risky to fast-allow
  '\bunlink\b'                              # single-file delete
  '\bsudo\b'
  '\bsu\b'
  '\beval\b'
  '\bexec\b'
  '\bsource\b'
  '^[[:space:]]*\.[[:space:]]'              # POSIX dot-source at start (. foo / . ./foo / . /foo)
  '\bdd[[:space:]]+if='
  '\bmkfs\b'
  '\bmount\b'
  '\bumount\b'
  '\bchmod\b'
  '\bchown\b'
  '\bkill(all)?\b'
  '\bpkill\b'
  '\bshutdown\b'
  '\breboot\b'
  '\bhalt\b'
  '\btruncate\b'
  '\bln[[:space:]]+'                        # any ln: symlink or hard link
  '\bmv\b'
  '\bcp\b'
  '>[[:space:]]*/'                          # redirect to absolute path
  '>>[[:space:]]*/'                         # append to absolute path
  '\bcurl\b.*\|[[:space:]]*(sh|bash|zsh)\b' # curl | sh
  '\bwget\b.*\|[[:space:]]*(sh|bash|zsh)\b'
  '\bgit[[:space:]]+push\b.*--force'
  '\bgit[[:space:]]+push\b.*-f\b'
  '\bgit[[:space:]]+reset[[:space:]]+--hard\b'
  '\bgit[[:space:]]+clean\b.*-f'
  '\bgit[[:space:]]+checkout\b.*--[[:space:]]*\.'
  '\bgit[[:space:]]+(commit|add|push|pull|merge|rebase|cherry-pick|tag|branch[[:space:]]+-[dD])\b'
  # `git stash` itself mutates (pushes working tree onto stash stack); only
  # `git stash list` and `git stash show` are read-only and pass through to
  # the allowlist below. Match mutating verbs, any dash-flag form, or bare
  # `git stash` terminated by end-of-string or a shell metachar.
  '\bgit[[:space:]]+stash[[:space:]]+(push|pop|drop|apply|save|clear|create|store|branch)\b'
  '\bgit[[:space:]]+stash[[:space:]]+-'
  '\bgit[[:space:]]+stash[[:space:]]*($|[;&|])'
  '\bdate[[:space:]]+[^|;&]*-(-set|s)\b'    # date setting system time (flag-specific)
  '\bmvn\b'                                 # always executes project code
  '\bgradle\b'
  '\b\./mvnw\b'
  '\b\./gradlew\b'
  '\bmake\b'                                # always runs Makefile target
  '\b(env|printenv|set|export|unset)\b'     # env var readout / mutation
  # BSD-style `ps` clusters (no leading dash) containing `e` show process
  # env, leaking secrets like ANTHROPIC_API_KEY. Matches `ps e`, `ps eww`,
  # `ps auxe`; deliberately does NOT match GNU-style `ps -e`, `ps -ef`
  # (where `-e` means "select all"), `ps aux`, or `ps --version`. The
  # `(^|[^-[:alnum:]])` prefix prevents the engine from sliding the match
  # past a leading dash, which the original `\bps\b…` pattern allowed.
  # Haiku doesn't reliably know these BSD semantics, so we catch them here.
  '(^|[^-[:alnum:]])ps[[:space:]]+(e|[a-z]+e)[a-z]*($|[[:space:]])'
  '\bssh\b'                                 # remote execution
  '\bscp\b'
  '\brsync\b'
  '\bnc\b'                                  # netcat / arbitrary I/O
  '\bnetcat\b'
  '\btee\b'                                 # writes files from stdin
  '\bcrontab\b'
  '\bfind\b[[:space:]].*(-delete|-exec|-execdir|-ok|-okdir)\b'
  '\bawk\b.*\bsystem[[:space:]]*\('         # awk shellout
  '\bawk\b.*\|[[:space:]]*getline\b'        # "cmd" | getline — awk reading from shell
  '\bg?awk\b.*\bprint[f]?[[:space:]]*.*>'   # awk printing to file
)

# Strip harmless redirects to /dev/null before checking deny patterns.
# Matches: >/dev/null, 2>/dev/null, &>/dev/null, 2>&1 >/dev/null, etc.
# The trailing [[:space:]]|$ anchor ensures /dev/null is a complete token —
# without it, >/dev/null.bak would strip to just .bak and bypass the
# >[[:space:]]*/ denylist check.
CMD_STRIPPED=$(printf '%s' "$CMD" | sed -E 's#([0-9]*&?)>[[:space:]]*/dev/null([[:space:]]+2>&1)?([[:space:]]|$)#\3#g')

for pat in "${DENY_PATTERNS[@]}"; do
  if printf '%s' "$CMD_STRIPPED" | grep -qE "$pat"; then
    log "DENY-PATTERN matched '$pat' for: $CMD"
    passthrough "matched risky pattern: $pat"
  fi
done

# ---- Compound detection ----------------------------------------------------
# If the command has any compound/redirect/substitution characters, don't
# trust the allowlist - send to Haiku for a real analysis. This kills the
# whole class of "allowlisted prefix + $(evil)" bypasses.
IS_COMPOUND=0
case "$CMD_STRIPPED" in
  *'|'*|*';'*|*'&'*|*'`'*|*'$('*|*'<'*|*'>'*|*'('*) IS_COMPOUND=1 ;;
esac
if [[ "$CMD" == *$'\n'* ]]; then IS_COMPOUND=1; fi

# ---- Fast allowlist (simple commands only) ---------------------------------
# Match ONLY the first token against an explicit list. No regex prefix
# tricks - we compare the bare command name. Anything with args that
# include shell specials has already been caught by compound detection.
ALLOW_TOKENS=(
  # Basic file/dir inspection
  ls ll la pwd stat file tree du df
  # Text read
  cat less more head tail wc
  # System/user info (no env vars)
  whoami hostname uname uptime date id type which
  # Search
  grep rg ripgrep ag fd locate
  # Data massage (read-only) - awk/find intentionally excluded:
  # awk has system()/getline pipes, find has -delete/-exec.
  # They roundtrip Haiku instead of being fast-allowed.
  jq yq xmllint column sort uniq cut tr basename dirname realpath readlink
  # Process listing intentionally excluded: `ps e` / `ps eww` discloses
  # process environment (secrets like ANTHROPIC_API_KEY). Roundtrip Haiku.
  # Constants
  true false
)

ALLOW_GIT_SUBCMDS=(
  status log diff show branch remote describe rev-parse
  ls-files ls-tree blame reflog shortlog
)

# gh (GitHub CLI) safe-pattern allowlist. Rather than chase every new
# unsafe `gh` verb in the denylist (a moving target), we assert what we
# know is read-only and route everything else to Haiku. Two shapes:
#
#   ALLOW_GH_SINGLE — `gh <sub>` where args don't affect safety
#                     (e.g. `gh status`, `gh search repos foo`)
#   ALLOW_GH_PAIRS  — `gh <sub> <action>` pairs (e.g. `gh pr list`)
#
# The check mirrors ALLOW_GIT_SUBCMDS below.
ALLOW_GH_SINGLE=(
  status version help search
)

ALLOW_GH_PAIRS=(
  "pr list" "pr view" "pr status" "pr checks" "pr diff"
  "issue list" "issue view" "issue status"
  "repo list" "repo view"
  "release list" "release view"
  "run list" "run view" "run watch"
  "workflow list" "workflow view"
  "auth status"
  "gist list" "gist view"
  "label list"
  "alias list"
  "extension list"
)

if [ "$IS_COMPOUND" = "0" ]; then
  # Extract first token
  read -r FIRST REST <<<"$CMD_STRIPPED"

  SIMPLE_ALLOW=0
  for t in "${ALLOW_TOKENS[@]}"; do
    if [ "$FIRST" = "$t" ]; then
      SIMPLE_ALLOW=1
      break
    fi
  done

  # Special-case: git with a read-only subcommand.
  if [ "$SIMPLE_ALLOW" = "0" ] && [ "$FIRST" = "git" ]; then
    read -r SUB THIRD _ <<<"$REST"
    for s in "${ALLOW_GIT_SUBCMDS[@]}"; do
      if [ "$SUB" = "$s" ]; then
        SIMPLE_ALLOW=1
        break
      fi
    done
    # git stash list / git stash show are read-only. Mutating stash verbs
    # (push, pop, drop, apply, …) and bare `git stash` were caught by the
    # denylist above, so reaching here with SUB=stash means a read-only
    # subcommand follows.
    if [ "$SIMPLE_ALLOW" = "0" ] && [ "$SUB" = "stash" ]; then
      case "$THIRD" in
        list|show) SIMPLE_ALLOW=1 ;;
      esac
    fi
  fi

  # Special-case: gh with a known safe single-sub or <sub> <action> pair.
  # See ALLOW_GH_SINGLE / ALLOW_GH_PAIRS above for the policy rationale.
  if [ "$SIMPLE_ALLOW" = "0" ] && [ "$FIRST" = "gh" ]; then
    read -r SUB THIRD _ <<<"$REST"
    for s in "${ALLOW_GH_SINGLE[@]}"; do
      if [ "$SUB" = "$s" ]; then
        SIMPLE_ALLOW=1
        break
      fi
    done
    if [ "$SIMPLE_ALLOW" = "0" ]; then
      gh_pair="$SUB $THIRD"
      for p in "${ALLOW_GH_PAIRS[@]}"; do
        if [ "$gh_pair" = "$p" ]; then
          SIMPLE_ALLOW=1
          break
        fi
      done
    fi
  fi

  if [ "$SIMPLE_ALLOW" = "1" ]; then
    log "FAST-ALLOW: $CMD"
    emit_decision "allow" "fast-allowlist (simple read-only command)"
  fi
fi

# ---- Haiku classifier fallback (direct Anthropic API via curl) -------------
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  log "ERROR ANTHROPIC_API_KEY not set"
  passthrough "ANTHROPIC_API_KEY not set"
fi

if ! command -v curl >/dev/null 2>&1; then
  log "ERROR curl not installed"
  passthrough "curl not available"
fi

# Strip the bash `command` builtin before sending to Haiku. `command foo`
# is semantically identical to `foo` (it just bypasses aliases/functions),
# but the word "command" confuses the classifier into thinking something
# dangerous is being executed. Strip at pipe-segment boundaries too, so
# `git diff | command head -n 50` becomes `git diff | head -n 50`.
CMD_FOR_CLASSIFIER=$(printf '%s' "$CMD" | sed -E 's/(^|[|;&])[[:space:]]*command[[:space:]]+/\1 /g')

PROMPT_TEXT="You are a shell command safety classifier. Classify the following command.

Reply with EXACTLY ONE WORD, nothing else:
- SAFE    if the command is strictly read-only: no file writes, no deletes, no network mutations, no package installs, no process kills, no privilege escalation, no git mutations (commit/push/reset/checkout), no build/test commands that execute project code, no reading of secret environment variables.
- UNSAFE  otherwise, or if you are unsure.

Command:
$CMD_FOR_CLASSIFIER"

REQUEST_BODY=$(jq -n \
  --arg model "$HAIKU_MODEL" \
  --arg prompt "$PROMPT_TEXT" \
  '{
    model: $model,
    max_tokens: 4,
    messages: [{role: "user", content: $prompt}]
  }')

RESPONSE=$(timeout "$HAIKU_TIMEOUT" curl -sS -X POST "$ANTHROPIC_API_URL" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  --data "$REQUEST_BODY" 2>/dev/null)
RC=$?

if [ $RC -ne 0 ] || [ -z "$RESPONSE" ]; then
  log "API-ERROR rc=$RC cmd: $CMD"
  passthrough "classifier HTTP call failed (rc=$RC)"
fi

API_ERROR=$(printf '%s' "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null)
if [ -n "$API_ERROR" ]; then
  log "API-ERROR '$API_ERROR' cmd: $CMD"
  passthrough "API error: $API_ERROR"
fi

# Strip whitespace AND punctuation so that trailing `.`, `!`, quotes, or
# other incidental characters don't defeat the strict match below. Then
# require an EXACT "SAFE" or "UNSAFE" verdict — anything else (including
# "not safe", "probably safe", truncated output, extra words) falls
# through to the unknown branch, which returns ask. Fuzzy *SAFE* matching
# previously would have mis-allowed responses like "NOT SAFE".
VERDICT=$(printf '%s' "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null | tr -d '[:space:][:punct:]' | tr '[:lower:]' '[:upper:]')

if [ -z "$VERDICT" ]; then
  log "API-NO-VERDICT response='$RESPONSE' cmd: $CMD"
  passthrough "classifier returned no verdict"
fi

case "$VERDICT" in
  UNSAFE)
    log "HAIKU-UNSAFE: $CMD"
    passthrough "Haiku classified as potentially mutating"
    ;;
  SAFE)
    log "HAIKU-SAFE: $CMD"
    emit_decision "allow" "Haiku classified as read-only"
    ;;
  *)
    log "HAIKU-UNKNOWN verdict='$VERDICT' cmd: $CMD"
    passthrough "Haiku returned unexpected verdict: $VERDICT"
    ;;
esac
