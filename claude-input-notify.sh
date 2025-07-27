#!/bin/bash
[ "$1" = -x ] && shift && set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude Code Input Notification Script
# Shows a visual notification when Claude Code is waiting for user input
# and switches focus back to the terminal window when OK is clicked
#
# Usage: claude-input-notify.sh [terminal_window_id]
#
# Debug mode: Set DEBUG_MODE=1 environment variable to enable debug output
# Example: DEBUG_MODE=1 ./claude-input-notify.sh

# Debug mode flag (set to 1 to enable debug output)
DEBUG_MODE=${DEBUG_MODE:-0}

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

# Get terminal window ID from first argument or try to detect it
TERMINAL_ID="$1"
debug_msg "Initial TERMINAL_ID from arg: '$TERMINAL_ID'"

# If no terminal ID provided, try to detect the parent terminal window
if [ -z "$TERMINAL_ID" ]; then
  # Method 1: Try to find gnome-terminal using xdotool (most reliable for Mint)
  TERMINAL_ID=$(xdotool search --onlyvisible --class "gnome-terminal" 2>/dev/null | head -n1)
  debug_msg "Method 1 - xdotool search for gnome-terminal: '$TERMINAL_ID'"

  # Method 2: If not found, try wmctrl to list all windows and find terminal
  if [ -z "$TERMINAL_ID" ]; then
    # Get list of all windows with their class names
    TERMINAL_INFO=$(wmctrl -lx 2>/dev/null | grep -i -E 'gnome-terminal|terminal\.Terminal|xfce4-terminal|mate-terminal' | head -n1)
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
        if echo "$FULL_WM_CLASS" | grep -E '"gnome-terminal"|"Gnome-terminal"|"xfce4-terminal"|"Xfce4-terminal"|"mate-terminal"|"Mate-terminal"|"Terminal"|"terminal"' > /dev/null 2>&1; then
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

# Check if we're already in the terminal window
if [ -n "$TERMINAL_ID" ] && [ -n "$CURRENT_WINDOW_ID" ] && [ "$TERMINAL_ID" = "$CURRENT_WINDOW_ID" ]; then
  debug_msg "Already in terminal window, skipping notification"
  echo "Already in terminal window, skipping notification"
  exit 0
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
NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"x-large\">✨ <b>Waiting for your input...</b> ✨</span>\n\n"
NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"medium\" style=\"italic\">Click OK to return to terminal</span>"

# Add debug info if debug mode is enabled
if [ "$DEBUG_MODE" -eq 1 ] && [ -n "$DEBUG_LOG" ]; then
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}\n\n<span size=\"small\" foreground=\"${TEXT_COLOR_DEBUG}\">────────────────────────────────</span>\n"
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"small\" foreground=\"${TEXT_COLOR_DEBUG}\"><tt>$(echo -e "$DEBUG_LOG")</tt></span>"
fi

# Show popup notification when Claude Code is waiting for user input
# Check if icon exists and add it to the command
if [ -f "$ICON_PATH" ]; then
  yad --button="<span size=\"large\">  <b>OK</b>  </span>:0" \
    --borders=$WINDOW_BORDERS \
    --text-align=center \
    --on-top \
    --undecorated \
    --skip-taskbar \
    --sticky \
    --center \
    --width=$WINDOW_WIDTH \
    --no-escape \
    --image="$ICON_PATH" \
    --image-on-top \
    --text="$NOTIFICATION_TEXT"
else
  # Fallback without icon if file not found
  yad --button="<span size=\"large\">  <b>OK</b>  </span>:0" \
    --borders=$WINDOW_BORDERS \
    --text-align=center \
    --on-top \
    --undecorated \
    --skip-taskbar \
    --sticky \
    --center \
    --width=$WINDOW_WIDTH \
    --no-escape \
    --text="$NOTIFICATION_TEXT"
fi

# If OK was clicked and terminal ID was found, focus the terminal
if [ $? -eq 0 ] && [ -n "$TERMINAL_ID" ]; then
  debug_msg "Attempting to focus terminal with ID: $TERMINAL_ID"

  # Method 1: Try wmctrl first (often more reliable)
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
      if wmctrl -xa "gnome-terminal" 2>/dev/null; then
        debug_msg "wmctrl -xa gnome-terminal succeeded"
      else
        debug_msg "All focus methods failed"
      fi
    fi
  fi
else
  debug_msg "Not focusing terminal - exit code: $?, TERMINAL_ID: '$TERMINAL_ID'"
fi

# Exit 0 to allow normal operation to continue
exit 0
