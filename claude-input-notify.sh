#!/bin/bash
[ "$1" = -x ] && shift && set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude Code Input Notification Script
# Shows a visual notification when Claude Code is waiting for user input
# and switches focus back to the terminal window when OK is clicked
#
# Usage: claude-input-notify.sh [terminal_window_id]
#        Can also read JSON from stdin to extract a message field
#
# Debug mode: Set DEBUG_MODE=1 environment variable to enable debug output
# Example: DEBUG_MODE=1 ./claude-input-notify.sh
#
# Test mode: Set TEST_MODE=1 to always show notification (bypass terminal check)
# Example: TEST_MODE=1 ./claude-input-notify.sh

# Debug mode flag (set to 1 to enable debug output)
DEBUG_MODE=${DEBUG_MODE:-0}

# Test mode flag (set to 1 to always show notification, even if already in terminal)
TEST_MODE=${TEST_MODE:-0}

# Visual settings for notification window
WINDOW_WIDTH=450
WINDOW_BORDERS=25
TEXT_COLOR_PRIMARY="#6B5B95"
TEXT_COLOR_DEBUG="#888888"

# Initialize debug log
DEBUG_LOG=""

# Function to add debug message
debug_msg() {
  local msg="$1"
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo "[DEBUG] $msg"
    DEBUG_LOG="${DEBUG_LOG}[DEBUG] $msg\n"
  fi
}

# Read JSON from stdin if available and extract message and other fields
STDIN_MESSAGE=""
STDIN_CWD=""
STDIN_SESSION_ID=""
if [ ! -t 0 ]; then
  # stdin is available (not a terminal)
  STDIN_DATA=$(cat)
  debug_msg "Received stdin data: '$STDIN_DATA'"

  # Try to extract fields from JSON using jq if available
  if command -v jq >/dev/null 2>&1 && [ -n "$STDIN_DATA" ]; then
    STDIN_MESSAGE=$(echo "$STDIN_DATA" | jq -r '.message // empty' 2>/dev/null)
    STDIN_CWD=$(echo "$STDIN_DATA" | jq -r '.cwd // empty' 2>/dev/null)
    STDIN_SESSION_ID=$(echo "$STDIN_DATA" | jq -r '.session_id // empty' 2>/dev/null)
    debug_msg "Extracted message using jq: '$STDIN_MESSAGE'"
    debug_msg "Extracted cwd using jq: '$STDIN_CWD'"
    debug_msg "Extracted session_id using jq: '$STDIN_SESSION_ID'"
  elif [ -n "$STDIN_DATA" ]; then
    # Fallback: try basic regex extraction if jq not available
    STDIN_MESSAGE=$(echo "$STDIN_DATA" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    STDIN_CWD=$(echo "$STDIN_DATA" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    debug_msg "Extracted message using sed: '$STDIN_MESSAGE'"
    debug_msg "Extracted cwd using sed: '$STDIN_CWD'"
  fi
fi

# Get terminal window ID from first argument or try to detect it
TERMINAL_ID="$1"
debug_msg "Initial TERMINAL_ID from arg: '$TERMINAL_ID'"

# If no terminal ID provided, try to detect the parent terminal window
if [ -z "$TERMINAL_ID" ]; then
  # Method 1: Try to find terminal using xdotool (most reliable for Mint)
  # Use exact match "^kitty$" to avoid matching kitty-panel
  TERMINAL_ID=$(xdotool search --onlyvisible --class "^kitty$" 2>/dev/null | head -n1)
  debug_msg "Method 1 - xdotool search for kitty: '$TERMINAL_ID'"

  if [ -z "$TERMINAL_ID" ]; then
    TERMINAL_ID=$(xdotool search --onlyvisible --class "gnome-terminal" 2>/dev/null | head -n1)
    debug_msg "Method 1 - xdotool search for gnome-terminal: '$TERMINAL_ID'"
  fi

  # Method 2: If not found, try wmctrl to list all windows and find terminal
  if [ -z "$TERMINAL_ID" ]; then
    # Get list of all windows with their class names
    # Use kitty\.kitty to match main kitty window, not kitty-panel
    TERMINAL_INFO=$(wmctrl -lx 2>/dev/null | grep -i -E 'kitty\.kitty|gnome-terminal|terminal\.Terminal|xfce4-terminal|mate-terminal' | head -n1)
    debug_msg "Method 2 - wmctrl output: '$TERMINAL_INFO'"

    if [ -n "$TERMINAL_INFO" ]; then
      # Extract window ID from wmctrl output (first field)
      TERMINAL_ID=$(echo "$TERMINAL_INFO" | awk '{print $1}')
      debug_msg "Extracted terminal ID from wmctrl: '$TERMINAL_ID'"
    fi
  fi

  # Method 3: If still not found, walk up process tree (original method, improved)
  if [ -z "$TERMINAL_ID" ]; then
    # Get the PID of the parent process
    PPID_CHAIN=$$
    debug_msg "Method 3 - Starting process tree walk with PID: $PPID_CHAIN"

    # Walk up the process tree to find a terminal emulator
    while [ "$PPID_CHAIN" -ne 1 ]; do
      # Get parent PID
      PPID_CHAIN=$(ps -o ppid= -p "$PPID_CHAIN" 2>/dev/null | tr -d ' ')
      [ -z "$PPID_CHAIN" ] && break
      debug_msg "Checking PPID: $PPID_CHAIN"

      # Check if this PID has an associated window
      WINDOW_ID=$(xdotool search --pid "$PPID_CHAIN" 2>/dev/null | head -n1)
      debug_msg "Window ID for PID $PPID_CHAIN: '$WINDOW_ID'"

      if [ -n "$WINDOW_ID" ]; then
        # Check if it's a terminal by looking at the window class
        FULL_WM_CLASS=$(xprop -id "$WINDOW_ID" WM_CLASS 2>/dev/null)
        debug_msg "Full WM_CLASS: '$FULL_WM_CLASS'"

        # Check for common terminal class names (case sensitive for better matching)
        # Use exact match for kitty to avoid matching kitty-panel
        if echo "$FULL_WM_CLASS" | grep -E '"kitty", "kitty"|"Kitty", "Kitty"|"gnome-terminal"|"Gnome-terminal"|"xfce4-terminal"|"Xfce4-terminal"|"mate-terminal"|"Mate-terminal"|"Terminal"|"terminal"' > /dev/null 2>&1; then
          TERMINAL_ID="$WINDOW_ID"
          debug_msg "Found terminal! Setting TERMINAL_ID=$TERMINAL_ID"
          break
        fi
      fi
    done
  fi
fi

debug_msg "Final terminal ID: ${TERMINAL_ID}"
echo "Found terminal ID: ${TERMINAL_ID}"

# Get the currently active window
CURRENT_WINDOW_ID=$(xdotool getactivewindow 2>/dev/null)
debug_msg "Current active window ID: ${CURRENT_WINDOW_ID}"

# Check if we're already in the terminal window (skip check if in test mode)
if [ "$TEST_MODE" -eq 0 ] && [ -n "$TERMINAL_ID" ] && [ -n "$CURRENT_WINDOW_ID" ] && [ "$TERMINAL_ID" = "$CURRENT_WINDOW_ID" ]; then
  debug_msg "Already in terminal window, skipping notification"
  echo "Already in terminal window, skipping notification"
  exit 0
fi

if [ "$TEST_MODE" -eq 1 ]; then
  debug_msg "Test mode enabled - showing notification regardless of current window"
fi


# Get the directory where this script is located
# Look for a 64x64 version first, fallback to original
ICON_PATH="${SCRIPT_DIR}/claude-logo-64.png"
if [ ! -f "$ICON_PATH" ]; then
  ICON_PATH="${SCRIPT_DIR}/claude-logo.png"
fi

# Prepare the notification text
NOTIFICATION_TEXT="<span size=\"xx-large\" weight=\"bold\" foreground=\"${TEXT_COLOR_PRIMARY}\">Claude Code</span>\n\n"
NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"large\">━━━━━━━━━━━━━━━━━━━━━━━━━━━</span>\n\n"

# Use stdin message if available, otherwise default message
if [ -n "$STDIN_MESSAGE" ]; then
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"x-large\">✨ <b>$STDIN_MESSAGE</b> ✨</span>\n\n"
else
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"x-large\">✨ <b>Waiting for your input...</b> ✨</span>\n\n"
fi

NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"medium\" style=\"italic\">Click OK to return to terminal</span>"

# Add debug info if debug mode is enabled
if [ "$DEBUG_MODE" -eq 1 ] && [ -n "$DEBUG_LOG" ]; then
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}\n\n<span size=\"small\" foreground=\"${TEXT_COLOR_DEBUG}\">────────────────────────────────</span>\n"
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"small\" foreground=\"${TEXT_COLOR_DEBUG}\"><tt>$(echo -e "$DEBUG_LOG")</tt></span>"
fi

# Show popup notification when Claude Code is waiting for user input
# Build image parameters if icon exists
IMAGE_PARAMS=""
if [ -f "$ICON_PATH" ]; then
  IMAGE_PARAMS="--image=$ICON_PATH --image-on-top"
fi

# Show the notification dialog
yad --button="<span size=\"large\">  <b>OK</b>  </span>:0" \
  --button="<span size=\"large\">  <b>Cancel</b>  </span>:1" \
  --borders=$WINDOW_BORDERS \
  --text-align=center \
  --on-top \
  --undecorated \
  --skip-taskbar \
  --sticky \
  --center \
  --width=$WINDOW_WIDTH \
  $IMAGE_PARAMS \
  --text="$NOTIFICATION_TEXT"

# Store yad exit code before defining functions
YAD_EXIT_CODE=$?

# Function to focus kitty internal window using remote control
focus_kitty_window() {
  local target_cwd="$1"
  debug_msg "Attempting to focus kitty window with cwd: '$target_cwd'"

  # Find kitty socket
  local kitty_socket=$(ls /tmp/kitty-* 2>/dev/null | command head -1)
  if [ -z "$kitty_socket" ]; then
    debug_msg "No kitty socket found"
    return 1
  fi
  debug_msg "Found kitty socket: $kitty_socket"

  # Get kitty windows info
  local kitty_info=$(kitty @ --to "unix:$kitty_socket" ls 2>/dev/null)
  if [ -z "$kitty_info" ]; then
    debug_msg "Failed to get kitty window info"
    return 1
  fi

  # Find window running claude with matching cwd
  local kitty_window_id=""
  if [ -n "$target_cwd" ] && command -v jq >/dev/null 2>&1; then
    # First try to match by cwd
    kitty_window_id=$(echo "$kitty_info" | jq -r --arg cwd "$target_cwd" '
      .[0].tabs[].windows[] |
      select(.foreground_processes[]? | (.cmdline[]? | test("claude"; "i")) and .cwd == $cwd) |
      .id' 2>/dev/null | command head -1)
    debug_msg "Kitty window ID matched by cwd: '$kitty_window_id'"
  fi

  # If no match by cwd, find any window running claude
  if [ -z "$kitty_window_id" ] && command -v jq >/dev/null 2>&1; then
    kitty_window_id=$(echo "$kitty_info" | jq -r '
      .[0].tabs[].windows[] |
      select(.foreground_processes[]? | .cmdline[]? | test("claude"; "i")) |
      .id' 2>/dev/null | command head -1)
    debug_msg "Kitty window ID (any claude): '$kitty_window_id'"
  fi

  if [ -n "$kitty_window_id" ]; then
    debug_msg "Focusing kitty internal window ID: $kitty_window_id"
    kitty @ --to "unix:$kitty_socket" focus-window --match "id:$kitty_window_id" 2>/dev/null
    local focus_result=$?

    # Switch to stack layout to maximize the focused window (full OS window)
    debug_msg "Switching to stack layout for full window"
    kitty @ --to "unix:$kitty_socket" goto-layout stack 2>/dev/null

    return $focus_result
  fi

  debug_msg "No claude window found in kitty"
  return 1
}

# If OK was clicked and terminal ID was found, focus the terminal
if [ $YAD_EXIT_CODE -eq 0 ] && [ -n "$TERMINAL_ID" ]; then
  debug_msg "Attempting to focus terminal with ID: $TERMINAL_ID"

  # Method 1: Try wmctrl first (often more reliable for X11 window focus)
  if wmctrl -i -a "$TERMINAL_ID" 2>/dev/null; then
    debug_msg "wmctrl -i -a succeeded"
  else
    debug_msg "wmctrl -i -a failed, trying xdotool"

    # Method 2: Try xdotool as fallback
    if xdotool windowactivate "$TERMINAL_ID" 2>/dev/null; then
      debug_msg "xdotool windowactivate succeeded"
    else
      debug_msg "xdotool windowactivate failed, trying wmctrl by class"

      # Method 3: Try activating by class name as last resort
      if wmctrl -xa "kitty" 2>/dev/null; then
        debug_msg "wmctrl -xa kitty succeeded"
      elif wmctrl -xa "gnome-terminal" 2>/dev/null; then
        debug_msg "wmctrl -xa gnome-terminal succeeded"
      else
        debug_msg "All focus methods failed"
      fi
    fi
  fi

  # For kitty: also focus the specific internal window running claude
  focus_kitty_window "$STDIN_CWD"
else
  debug_msg "Not focusing terminal - exit code: $YAD_EXIT_CODE, TERMINAL_ID: '$TERMINAL_ID'"
fi

# Exit 0 to allow normal operation to continue
exit 0
