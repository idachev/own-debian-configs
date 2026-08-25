#!/bin/bash
# Grok context-usage warning. Sibling of claude-input-notify.sh: same
# popup when this session is at or above CONTEXT_WARN_PERCENT.
# First qualifying end_turn (usage just at/over the floor) shows immediately.
# After that the dialog repeats every Nth qualifying fire (default 3).
#
# Wired from ~/.grok/hooks/context-usage-warn.json (pointer only, like
# Claude Code's ~/bin/claude-input-notify.sh hook).
# Reads ~/.grok/sessions/<cwd>/<id>/signals.json — hook stdin has no usage %.
# Keep stdout empty: Stop hooks parse stdout JSON as a stop decision.
#
# Env:
#   CONTEXT_WARN_PERCENT=65     usage floor that starts counting (default 65)
#   CONTEXT_WARN_EVERY=3        after the first show, repeat every N fires
#   CONTEXT_WARN_FORCE=1        notify even when usage is below the threshold
#   CONTEXT_WARN_NOTIFY=path    override the popup script
#   CONTEXT_WARN_LOG=path       override the log file (/dev/null to disable)
#   TEST_MODE=1                 passed through to claude-input-notify.sh
#                               (show even when the terminal is focused)

[ "$1" = -x ] && shift && set -x

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROK_HOME="${GROK_HOME:-$HOME/.grok}"
NOTIFY_SCRIPT="${CONTEXT_WARN_NOTIFY:-$SCRIPT_DIR/claude-input-notify.sh}"
WARN_AT="${CONTEXT_WARN_PERCENT:-65}"
EVERY="${CONTEXT_WARN_EVERY:-3}"
STATE_DIR="${GROK_HOME}/hooks/state"
WARN_LOG="${CONTEXT_WARN_LOG:-$HOME/tmp/claude-logs/grok-context-warn.log}"

log() {
  command mkdir -p "$(command dirname "$WARN_LOG")" 2>/dev/null || true
  command printf '%s %s\n' "$(command date -Iseconds 2>/dev/null || command date +%Y-%m-%dT%H:%M:%S%z)" "$*" >>"$WARN_LOG" 2>/dev/null || true
}

if ! command -v jq >/dev/null 2>&1; then
  log "skip jq not found"
  exit 0
fi

case "$WARN_AT" in
  ''|*[!0-9]*)
    log "skip bad CONTEXT_WARN_PERCENT='$WARN_AT'"
    exit 0
    ;;
esac
if [ "$WARN_AT" -gt 100 ]; then
  log "skip CONTEXT_WARN_PERCENT='$WARN_AT' over 100"
  exit 0
fi
case "$EVERY" in
  ''|*[!0-9]*|0)
    log "skip bad CONTEXT_WARN_EVERY='$EVERY'"
    exit 0
    ;;
esac

INPUT=$(command cat)
REASON=$(printf '%s' "$INPUT" | command jq -r '.reason // empty' 2>/dev/null || true)
SESSION_ID="${GROK_SESSION_ID:-$(printf '%s' "$INPUT" | command jq -r '.sessionId // .session_id // empty' 2>/dev/null || true)}"
CWD="${GROK_WORKSPACE_ROOT:-$(printf '%s' "$INPUT" | command jq -r '.cwd // .workspaceRoot // empty' 2>/dev/null || true)}"
# Session dirs are encoded without a trailing slash; hook cwd often has one.
case "$CWD" in
  /) ;;
  */) CWD="${CWD%/}" ;;
esac

# Session-end Stop is observe-only and has no turn left to warn about.
if [ "$REASON" != "end_turn" ] && [ "${CONTEXT_WARN_FORCE:-0}" != "1" ]; then
  log "skip reason=${REASON:-empty} session=${SESSION_ID:-none}"
  exit 0
fi

if [ -z "$SESSION_ID" ]; then
  log "skip no session id"
  exit 0
fi

find_signals() {
  local sid="$1" cwd="$2" home="$3" enc="" found=""
  if [ -n "$cwd" ]; then
    enc=$(command python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$cwd" 2>/dev/null || true)
    if [ -n "$enc" ] && [ -f "$home/sessions/$enc/$sid/signals.json" ]; then
      printf '%s\n' "$home/sessions/$enc/$sid/signals.json"
      return 0
    fi
  fi
  found=$(command find "$home/sessions" -mindepth 2 -maxdepth 3 \
    -path "*/$sid/signals.json" -print -quit 2>/dev/null || true)
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
  fi
  return 0
}

SIGNALS=$(find_signals "$SESSION_ID" "$CWD" "$GROK_HOME")
if [ -z "$SIGNALS" ] || [ ! -f "$SIGNALS" ]; then
  log "skip no signals.json session=$SESSION_ID cwd=${CWD:-none}"
  exit 0
fi

PCT=$(command jq -r '.contextWindowUsage // empty' "$SIGNALS" 2>/dev/null || true)
USED=$(command jq -r '.contextTokensUsed // empty' "$SIGNALS" 2>/dev/null || true)
WINDOW=$(command jq -r '.contextWindowTokens // empty' "$SIGNALS" 2>/dev/null || true)

case "$PCT" in
  ''|*[!0-9]*)
    log "skip bad percent='$PCT' file=$SIGNALS"
    exit 0
    ;;
esac

# Count qualifying end_turn fires while usage stays at/above the floor.
# Compact / rewind below the floor resets the counter.
STATE_FILE="$STATE_DIR/${SESSION_ID}.count"
if [ "$PCT" -lt "$WARN_AT" ] && [ "${CONTEXT_WARN_FORCE:-0}" != "1" ]; then
  command rm -f "$STATE_FILE"
  log "ok below threshold pct=$PCT warn_at=$WARN_AT"
  exit 0
fi

COUNT=0
if [ -f "$STATE_FILE" ]; then
  COUNT=$(command cat "$STATE_FILE" 2>/dev/null || command printf '%s' 0)
  case "$COUNT" in
    ''|*[!0-9]*) COUNT=0 ;;
  esac
fi
COUNT=$((COUNT + 1))
command mkdir -p "$STATE_DIR"
printf '%s\n' "$COUNT" >"$STATE_FILE"

# Fire 1: first time over the threshold. Then 1+EVERY, 1+2*EVERY, ...
OFFSET=$(( (COUNT - 1) % EVERY ))
if [ "$OFFSET" -ne 0 ]; then
  log "count $COUNT (no dialog, next in $((EVERY - OFFSET))) pct=$PCT session=$SESSION_ID"
  exit 0
fi

COMPACT_AT="${GROK_AUTO_COMPACT_THRESHOLD_PERCENT:-}"
if [ -z "$COMPACT_AT" ] && [ -f "$GROK_HOME/config.toml" ]; then
  COMPACT_AT=$(command sed -n 's/^[[:space:]]*auto_compact_threshold_percent[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    "$GROK_HOME/config.toml" | command tail -n 1)
fi
COMPACT_AT="${COMPACT_AT:-90}"

MSG="Context ${PCT}% full"
if [ -n "$USED" ] && [ -n "$WINDOW" ]; then
  MSG="${MSG} (${USED} / ${WINDOW} tokens)"
fi
MSG="${MSG}. Auto-compact at ${COMPACT_AT}%."

log "warn count=$COUNT (first or every $EVERY) pct=$PCT session=$SESSION_ID msg=$MSG"

if [ ! -x "$NOTIFY_SCRIPT" ]; then
  log "notify script missing: $NOTIFY_SCRIPT"
  exit 0
fi

# idle_prompt is on claude-input-notify.sh's Grok allowlist, so the popup
# matches "waiting for input" (same dialog, focus rules, terminal jump).
PAYLOAD=$(command jq -n \
  --arg msg "$MSG" \
  --arg cwd "$CWD" \
  --arg sid "$SESSION_ID" \
  '{
    message: $msg,
    cwd: $cwd,
    sessionId: $sid,
    hookEventName: "notification",
    notificationType: "idle_prompt"
  }')

# Capture notify output so it cannot leak JSON onto Stop-hook stdout.
NOTIFY_OUT=$(printf '%s\n' "$PAYLOAD" | "$NOTIFY_SCRIPT" 2>&1) || true
log "notify: $(printf '%s' "$NOTIFY_OUT" | command tr '\n' ' ' | command cut -c1-300)"

exit 0
