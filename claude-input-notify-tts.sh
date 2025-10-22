#!/bin/bash
[ "$1" = -x ] && shift && set -x

# Claude Code TTS (Text-to-Speech) Script
# Reads JSON from stdin, extracts the message field, and speaks it using Piper TTS
#
# Usage: echo '{"message":"Hello"}' | claude-input-notify-tts.sh
#
# Debug mode: Set DEBUG_MODE=1 environment variable to enable debug output
# Example: DEBUG_MODE=1 ./claude-input-notify-tts.sh

# Debug mode flag (set to 1 to enable debug output)
DEBUG_MODE=${DEBUG_MODE:-0}

# Function to add debug message
debug_msg() {
  local msg="$1"
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "[DEBUG] $msg" >&2
  fi
}

# Read JSON from stdin if available and extract message
STDIN_MESSAGE=""
if [ ! -t 0 ]; then
  # stdin is available (not a terminal)
  STDIN_DATA=$(cat)
  debug_msg "Received stdin data: '$STDIN_DATA'"

  # Try to extract message field from JSON using jq if available
  if command -v jq >/dev/null 2>&1 && [ -n "$STDIN_DATA" ]; then
    STDIN_MESSAGE=$(echo "$STDIN_DATA" | jq -r '.message // empty' 2>/dev/null)
    debug_msg "Extracted message using jq: '$STDIN_MESSAGE'"
  elif [ -n "$STDIN_DATA" ]; then
    # Fallback: try basic regex extraction if jq not available
    STDIN_MESSAGE=$(echo "$STDIN_DATA" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    debug_msg "Extracted message using sed: '$STDIN_MESSAGE'"
  fi
fi

# Use stdin message if available, otherwise default message
if [ -z "$STDIN_MESSAGE" ]; then
  STDIN_MESSAGE="Waiting for your input"
  debug_msg "No message from stdin, using default: '$STDIN_MESSAGE'"
fi

# Call piper-exec.sh with the message
PIPER_EXEC="/home/idachev/lib/piper/bin/piper-exec.sh"

if [ ! -x "$PIPER_EXEC" ]; then
  debug_msg "Error: piper-exec.sh not found or not executable at $PIPER_EXEC"
  echo "Error: piper-exec.sh not found or not executable at $PIPER_EXEC" >&2
  exit 1
fi

debug_msg "Calling piper-exec.sh with message: '$STDIN_MESSAGE'"

# Pass the message to piper-exec.sh as a quoted argument and run in background
"$PIPER_EXEC" "$STDIN_MESSAGE" &

exit 0
