#!/bin/bash
# Claude Code PreToolUse hook: auto-approve safe read-only Bash commands
#
# Reads PreToolUse JSON from stdin. For Bash tool calls, decides:
#   - allow: command is clearly safe / read-only
#   - ask:   command is potentially mutating, user must confirm
#   - deny:  recursion guard tripped
# Decision is emitted on stdout as hookSpecificOutput JSON.
#
# Flow:
#   1. Non-Bash tool calls pass through untouched
#   2. Recursion guard (fails closed with deny)
#   3. Fast denylist of obviously dangerous patterns - straight to ask
#   4. If command contains any compound/redirect/substitution characters
#      (| ; & ` $( < >  newline), skip the allowlist and go straight
#      to the Haiku classifier. The allowlist is too easy to fool in
#      compound commands, so we pay the ~1s classifier latency.
#   5. Simple single-token command: tokenwise allowlist match -> allow
#   6. Fall back to Haiku classifier via direct Anthropic API
#
# On any error, defaults to "ask" (fail-safe).
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

# ---- Parse stdin -----------------------------------------------------------
INPUT=$(cat)
if [ -z "$INPUT" ]; then
  log "ERROR empty stdin"
  emit_decision "ask" "empty hook input"
fi

if ! command -v jq >/dev/null 2>&1; then
  log "ERROR jq not installed"
  emit_decision "ask" "jq not installed on host"
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
# If the classifier subprocess somehow re-entered this hook, fail closed.
# The classifier only needs to output one word and should never invoke Bash.
# Denying here also hardens against the env var being set accidentally in the
# outer shell.
if [ "${CLAUDE_BASH_SAFETY_INFLIGHT:-0}" = "1" ]; then
  emit_decision "deny" "safety-check subprocess should not invoke Bash"
fi

if [ -z "$CMD" ]; then
  log "ERROR bash tool call with empty command"
  emit_decision "ask" "empty command"
fi

# ---- Fast denylist ---------------------------------------------------------
# Obviously dangerous patterns. Match anywhere in the command, including
# inside pipelines and command substitutions - denylist beats compound check.
# We return "ask" (not "deny") so the user can still approve case-by-case.
DENY_PATTERNS=(
  '\brm\b'                                  # any rm - too risky to fast-allow
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
  '\bln[[:space:]]+-[a-zA-Z]*s'             # symlink creation
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
  '\bnpm[[:space:]]+(install|uninstall|publish|run)\b'
  '\byarn[[:space:]]+(add|remove|publish)\b'
  '\bpnpm[[:space:]]+(add|remove|publish)\b'
  '\bpip[[:space:]]+(install|uninstall)\b'
  '\bapt(-get)?[[:space:]]+(install|remove|purge|update|upgrade)\b'
  '\bdocker[[:space:]]+(run|rm|rmi|kill|stop|exec|build|push|pull)\b'
  '\bkubectl[[:space:]]+(apply|delete|create|edit|patch|exec)\b'
  '\bmvn\b'
  '\bgradle\b'
  '\b\./mvnw\b'
  '\b\./gradlew\b'
  '\bterraform\b'
  '\bmake\b'
  '\b(env|printenv|set|export|unset)\b'     # env var readout / mutation
  '\bps\b[[:space:]]+[a-z]*e[a-z]*\b'       # ps BSD flag cluster w/ `e` = show process env
  '\bssh\b'                                 # remote execution
  '\bscp\b'
  '\brsync\b'
  '\bnc\b'                                  # netcat / arbitrary I/O
  '\bnetcat\b'
  '\btee\b'                                 # writes files from stdin
  '\bcrontab\b'
  '\bsystemctl\b'
  '\bjournalctl\b'                          # may dump secrets from logs
  '\bfind\b[[:space:]].*(-delete|-exec|-execdir|-ok|-okdir)\b'
  '\bawk\b.*\bsystem[[:space:]]*\('         # awk shellout
  '\bawk\b.*\|[[:space:]]*getline\b'        # "cmd" | getline — awk reading from shell
  '\bg?awk\b.*\bprint[f]?[[:space:]]*.*>'   # awk printing to file
)

# Strip harmless redirects to /dev/null before checking deny patterns.
# Matches: >/dev/null, 2>/dev/null, &>/dev/null, 2>&1 >/dev/null, etc.
CMD_STRIPPED=$(printf '%s' "$CMD" | sed -E 's#([0-9]*&?)>[[:space:]]*/dev/null([[:space:]]+2>&1)?##g')

for pat in "${DENY_PATTERNS[@]}"; do
  if printf '%s' "$CMD_STRIPPED" | grep -qE "$pat"; then
    log "DENY-PATTERN matched '$pat' for: $CMD"
    emit_decision "ask" "matched risky pattern: $pat"
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
    read -r SUB _ <<<"$REST"
    for s in "${ALLOW_GIT_SUBCMDS[@]}"; do
      if [ "$SUB" = "$s" ]; then
        SIMPLE_ALLOW=1
        break
      fi
    done
  fi

  if [ "$SIMPLE_ALLOW" = "1" ]; then
    log "FAST-ALLOW: $CMD"
    emit_decision "allow" "fast-allowlist (simple read-only command)"
  fi
fi

# ---- Haiku classifier fallback (direct Anthropic API via curl) -------------
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  log "ERROR ANTHROPIC_API_KEY not set"
  emit_decision "ask" "ANTHROPIC_API_KEY not set"
fi

if ! command -v curl >/dev/null 2>&1; then
  log "ERROR curl not installed"
  emit_decision "ask" "curl not available"
fi

PROMPT_TEXT="You are a shell command safety classifier. Classify the following command.

Reply with EXACTLY ONE WORD, nothing else:
- SAFE    if the command is strictly read-only: no file writes, no deletes, no network mutations, no package installs, no process kills, no privilege escalation, no git mutations (commit/push/reset/checkout), no build/test commands that execute project code, no reading of secret environment variables.
- UNSAFE  otherwise, or if you are unsure.

Command:
$CMD"

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
  emit_decision "ask" "classifier HTTP call failed (rc=$RC)"
fi

API_ERROR=$(printf '%s' "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null)
if [ -n "$API_ERROR" ]; then
  log "API-ERROR '$API_ERROR' cmd: $CMD"
  emit_decision "ask" "API error: $API_ERROR"
fi

VERDICT=$(printf '%s' "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')

if [ -z "$VERDICT" ]; then
  log "API-NO-VERDICT response='$RESPONSE' cmd: $CMD"
  emit_decision "ask" "classifier returned no verdict"
fi

case "$VERDICT" in
  *UNSAFE*)
    log "HAIKU-UNSAFE: $CMD"
    emit_decision "ask" "Haiku classified as potentially mutating"
    ;;
  *SAFE*)
    log "HAIKU-SAFE: $CMD"
    emit_decision "allow" "Haiku classified as read-only"
    ;;
  *)
    log "HAIKU-UNKNOWN verdict='$VERDICT' cmd: $CMD"
    emit_decision "ask" "Haiku returned unexpected verdict: $VERDICT"
    ;;
esac
