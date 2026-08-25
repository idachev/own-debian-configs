#!/bin/bash
[ "$1" = -x ] && shift && set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Agent input notification (Claude Code + Grok CLI)
# Shows a visual notification when an agent is waiting for user input
# and switches focus back to the terminal window when OK is clicked.
# Linux: YAD popup + xdotool/wmctrl. macOS: dark tkinter popup (same palette),
# osascript fallback.
# Grok fires use grok-logo-64.png + "Grok CLI"; Claude uses the asterisk.
#
# Usage: claude-input-notify.sh [terminal_window_id]
#        Can also read JSON from stdin to extract a message field
#
# Debug mode: Set DEBUG_MODE=1 environment variable to enable debug output
# Example: DEBUG_MODE=1 ./claude-input-notify.sh
#
# Test mode: Set TEST_MODE=1 to always show notification (bypass terminal check)
# Example: TEST_MODE=1 ./claude-input-notify.sh
#
# Grok filter: only notify on user-input / fully-idle types (not per-task
# background completions). Override allowlist with NOTIFY_GROK_TYPES.
# Default: permission_prompt,idle_prompt,elicitation_dialog
# Example: NOTIFY_GROK_TYPES=permission_prompt,idle_prompt ./claude-input-notify.sh
#
# Suppress a whole source: NOTIFY_SKIP_SOURCES=grok
# Auto-close the macOS dialog after N seconds: NOTIFY_GIVE_UP=30

# Debug mode flag (set to 1 to enable debug output)
DEBUG_MODE=${DEBUG_MODE:-0}

# Test mode flag (set to 1 to always show notification, even if already in terminal)
TEST_MODE=${TEST_MODE:-0}

iso_now() {
  date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z
}

is_darwin() {
  [ "$(uname -s)" = Darwin ]
}

proc_cmd() {
  local pid="$1"
  if [ -r "/proc/$pid/cmdline" ]; then
    command tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | command head -n1
  else
    ps -p "$pid" -o command= 2>/dev/null
  fi
}

proc_ppid() {
  local pid="$1"
  if [ -r "/proc/$pid/status" ]; then
    command awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null
  else
    ps -p "$pid" -o ppid= 2>/dev/null | command tr -d '[:space:]'
  fi
}

as_escape() {
  printf '%s' "$1" | command sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

macos_frontmost_name() {
  osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null
}

macos_app_name_for_pid() {
  local pid="$1" n cmd
  n=$(osascript -e "tell application \"System Events\" to get name of first process whose unix id is $pid" 2>/dev/null) || true
  if [ -n "$n" ]; then
    printf '%s\n' "$n"
    return 0
  fi
  cmd=$(proc_cmd "$pid")
  case "$cmd" in
    *supacode.app*|*[Ss]upacode*) printf 'Supacode\n' ;;
    *kitty.app*|*[Kk]itty*) printf 'kitty\n' ;;
    *[Gg]hostty*) printf 'Ghostty\n' ;;
    *iTerm*) printf 'iTerm\n' ;;
    *Warp.app*|*[Ww]arp*) printf 'Warp\n' ;;
    *Alacritty*) printf 'Alacritty\n' ;;
    *WezTerm*|*wezterm*) printf 'WezTerm\n' ;;
    *Cursor.app*) printf 'Cursor\n' ;;
    *Windsurf*) printf 'Windsurf\n' ;;
    *"Visual Studio Code"*|*Code.app*) printf 'Visual Studio Code\n' ;;
    *Terminal.app*) printf 'Terminal\n' ;;
    *) return 1 ;;
  esac
}

is_macos_terminal_cmd() {
  echo "$1" | command grep -qiE \
    'supacode\.app|/zmx/zmx|[Kk]itty|[Gg]hostty|iTerm|Alacritty|WezTerm|Warp\.app|Cursor\.app|Windsurf|Visual Studio Code|Terminal\.app'
}

find_macos_terminal_pid() {
  local pid="${1:-$$}"
  while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
    if is_macos_terminal_cmd "$(proc_cmd "$pid")"; then
      printf '%s\n' "$pid"
      return 0
    fi
    pid=$(proc_ppid "$pid")
  done
  return 1
}

names_equal_ci() {
  local a b
  a=$(printf '%s' "$1" | command tr '[:upper:]' '[:lower:]')
  b=$(printf '%s' "$2" | command tr '[:upper:]' '[:lower:]')
  [ -n "$a" ] && [ "$a" = "$b" ]
}

show_macos_osascript_dialog() {
  local title="$1" body="$2" icon="$3"
  local title_q body_q icon_line="" give_up="" script out
  title_q=$(as_escape "$title")
  body_q=$(as_escape "$body")
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    icon_line="with icon POSIX file \"$(as_escape "$icon")\""
  fi
  if [ -n "${NOTIFY_GIVE_UP:-}" ]; then
    give_up="giving up after ${NOTIFY_GIVE_UP}"
  fi
  script="try
  set d to display dialog \"${body_q}\" with title \"${title_q}\" buttons {\"Cancel\", \"OK\"} default button \"OK\" cancel button \"Cancel\" ${icon_line} ${give_up}
  return \"OK\"
on error
  return \"CANCEL\"
end try"
  out=$(osascript -e "$script" 2>/dev/null) || true
  # Retry without icon only when osascript failed to present (empty out).
  # Cancel also yields non-OK; do not show the dialog a second time.
  if [ -z "$out" ] && [ -n "$icon_line" ]; then
    script="try
  set d to display dialog \"${body_q}\" with title \"${title_q}\" buttons {\"Cancel\", \"OK\"} default button \"OK\" cancel button \"Cancel\" ${give_up}
  return \"OK\"
on error
  return \"CANCEL\"
end try"
    out=$(osascript -e "$script" 2>/dev/null) || true
  fi
  if [ -z "$out" ]; then
    osascript -e "display notification \"${body_q}\" with title \"${title_q}\"" 2>/dev/null || true
    return 1
  fi
  [ "$out" = "OK" ]
}

# Dark popup that matches the Linux YAD palette (ivory / purple on near-black).
# Exit 0=OK, 1=Cancel, 2=backend failed (caller falls back).
show_macos_tk_dialog() {
  local title="$1" body="$2" cwd="$3" icon="$4" color="$5" debug_extra="${6:-}"
  command python3 - "$title" "$body" "$cwd" "$icon" "$color" "${NOTIFY_GIVE_UP:-}" "$debug_extra" <<'PY'
import os
import sys

try:
    import tkinter as tk
except Exception:
    sys.exit(2)

title, body, cwd, icon, color, give_up, debug = (sys.argv + [""] * 7)[1:8]
BG = "#1C1C1E"
IVORY = "#E8DFD0"
DIM = "#888888"
BTN_BG = "#3A3A3C"
BTN_HOVER = "#4A4A4E"
SEP = "#3A3A3C"
WIDTH = 450
if not color:
    color = IVORY

try:
    root = tk.Tk()
except Exception:
    sys.exit(2)

result = {"ok": False}

def finish(ok):
    result["ok"] = ok
    root.destroy()

root.title(title)
root.configure(bg=BG)
root.overrideredirect(True)
root.resizable(False, False)
try:
    root.attributes("-topmost", True)
except tk.TclError:
    pass

outer = tk.Frame(root, bg=BG, padx=25, pady=20)
outer.pack(fill="both", expand=True)

if icon and os.path.isfile(icon):
    try:
        img = tk.PhotoImage(file=icon)
        if img.width() > 64:
            factor = max(1, img.width() // 64)
            img = img.subsample(factor, factor)
        il = tk.Label(outer, image=img, bg=BG)
        il.image = img
        il.pack(pady=(0, 10))
    except tk.TclError:
        pass

tk.Label(
    outer, text=title, bg=BG, fg=color,
    font=("Helvetica", 20, "bold"), wraplength=WIDTH - 50, justify="center",
).pack(pady=(0, 8))
tk.Frame(outer, bg=SEP, height=1).pack(fill="x", pady=8)
tk.Label(
    outer, text="✨ " + body + " ✨", bg=BG, fg=IVORY,
    font=("Helvetica", 16, "bold"), wraplength=WIDTH - 50, justify="center",
).pack(pady=(4, 8))
if cwd:
    tk.Label(
        outer, text=cwd, bg=BG, fg=DIM,
        font=("Helvetica", 11), wraplength=WIDTH - 50, justify="center",
    ).pack()
tk.Label(
    outer, text="Click OK to return to terminal", bg=BG, fg=DIM,
    font=("Helvetica", 12, "italic"), wraplength=WIDTH - 50, justify="center",
).pack(pady=(8, 12))
if debug:
    tk.Label(
        outer, text=debug, bg=BG, fg=DIM,
        font=("Menlo", 9), wraplength=WIDTH - 50, justify="left",
    ).pack(pady=(0, 8))

btns = tk.Frame(outer, bg=BG)
btns.pack(pady=(4, 0))

def make_btn(text, cmd, default=False):
    bg = "#4A4458" if default else BTN_BG
    fg = color if default else IVORY
    lbl = tk.Label(
        btns, text="  " + text + "  ", bg=bg, fg=fg,
        font=("Helvetica", 14, "bold"), padx=16, pady=8, cursor="hand2",
    )
    lbl.pack(side="left", padx=8)
    lbl.bind("<Button-1>", lambda _e: cmd())
    lbl.bind("<Enter>", lambda _e: lbl.configure(bg=BTN_HOVER))
    lbl.bind("<Leave>", lambda _e, b=bg: lbl.configure(bg=b))

make_btn("OK", lambda: finish(True), default=True)
make_btn("Cancel", lambda: finish(False))
root.bind("<Return>", lambda _e: finish(True))
root.bind("<Escape>", lambda _e: finish(False))

root.update_idletasks()
w = max(WIDTH, root.winfo_reqwidth())
h = root.winfo_reqheight()
x = (root.winfo_screenwidth() - w) // 2
y = max(40, (root.winfo_screenheight() - h) // 3)
root.geometry("%dx%d+%d+%d" % (w, h, x, y))
root.lift()
root.focus_force()
if give_up.isdigit() and int(give_up) > 0:
    root.after(int(give_up) * 1000, lambda: finish(True))
root.mainloop()
sys.exit(0 if result["ok"] else 1)
PY
}

show_macos_dialog() {
  local title="$1" body="$2" cwd="$3" icon="$4" color="$5" debug_extra="${6:-}"
  local rc=2
  if command -v python3 >/dev/null 2>&1; then
    show_macos_tk_dialog "$title" "$body" "$cwd" "$icon" "$color" "$debug_extra"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] && return 1
  fi
  local plain="$title

$body"
  if [ -n "$cwd" ]; then
    plain="$plain

$cwd"
  fi
  plain="$plain

Click OK to return to terminal"
  if [ -n "$debug_extra" ]; then
    plain="$plain

$debug_extra"
  fi
  show_macos_osascript_dialog "$title" "$plain" "$icon"
}

focus_macos_terminal() {
  local pid="$1" app="$2"
  if [ -n "${SUPACODE_SOCKET_PATH:-}" ] && command -v supacode >/dev/null 2>&1; then
    debug_msg "Focusing Supacode via CLI"
    command supacode >/dev/null 2>&1 || true
    if [ -n "${SUPACODE_TAB_ID:-}" ] && [ -n "${SUPACODE_SURFACE_ID:-}" ]; then
      command supacode surface focus -t "$SUPACODE_TAB_ID" -s "$SUPACODE_SURFACE_ID" >/dev/null 2>&1 || true
    fi
    return 0
  fi
  if [ -n "$app" ]; then
    debug_msg "Activating macOS app: $app"
    osascript -e "tell application \"$(as_escape "$app")\" to activate" 2>/dev/null && return 0
  fi
  if [ -n "$pid" ]; then
    debug_msg "Setting frontmost by pid: $pid"
    osascript -e "tell application \"System Events\" to set frontmost of first process whose unix id is $pid to true" 2>/dev/null && return 0
  fi
  return 1
}

# Visual settings for notification window
WINDOW_WIDTH=450
WINDOW_BORDERS=25
TEXT_COLOR_CLAUDE="#6B5B95"
# Ivory — the black comet disappears on dark GTK/YAD themes
TEXT_COLOR_GROK="#E8DFD0"
TEXT_COLOR_PRIMARY="$TEXT_COLOR_CLAUDE"
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
STDIN_EVENT=""
STDIN_NOTIFY_TYPE=""
STDIN_DATA=""
if [ ! -t 0 ]; then
  # stdin is available (not a terminal)
  STDIN_DATA=$(cat)
  debug_msg "Received stdin data: '$STDIN_DATA'"

  # Try to extract fields from JSON using jq if available
  if command -v jq >/dev/null 2>&1 && [ -n "$STDIN_DATA" ]; then
    # Claude Code sends snake_case (session_id, hook_event_name); Grok sends the
    # same envelope in camelCase (sessionId, hookEventName) and adds
    # notificationType. `message` and `cwd` are spelled the same in both.
    STDIN_MESSAGE=$(echo "$STDIN_DATA" | jq -r '.message // empty' 2>/dev/null)
    STDIN_CWD=$(echo "$STDIN_DATA" | jq -r '.cwd // .workspaceRoot // empty' 2>/dev/null)
    STDIN_SESSION_ID=$(echo "$STDIN_DATA" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
    STDIN_EVENT=$(echo "$STDIN_DATA" | jq -r '.hook_event_name // .hookEventName // empty' 2>/dev/null)
    STDIN_NOTIFY_TYPE=$(echo "$STDIN_DATA" | jq -r '.notification_type // .notificationType // empty' 2>/dev/null)
    debug_msg "Extracted message using jq: '$STDIN_MESSAGE'"
    debug_msg "Extracted cwd using jq: '$STDIN_CWD'"
    debug_msg "Extracted session_id using jq: '$STDIN_SESSION_ID'"
    debug_msg "Extracted event using jq: '$STDIN_EVENT' type: '$STDIN_NOTIFY_TYPE'"
  elif [ -n "$STDIN_DATA" ]; then
    # Fallback: try basic regex extraction if jq not available
    STDIN_MESSAGE=$(echo "$STDIN_DATA" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    STDIN_CWD=$(echo "$STDIN_DATA" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    debug_msg "Extracted message using sed: '$STDIN_MESSAGE'"
    debug_msg "Extracted cwd using sed: '$STDIN_CWD'"
  fi
fi

# Walk up from this hook to the agent process that spawned it. Its PID pins the
# exact kitty window even when several sessions share a working directory.
find_agent_pid() {
  local re="$1" pid="$PPID" name
  while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
    name=$(proc_cmd "$pid")
    name="${name##*/}"
    name="${name%% *}"
    if echo "$name" | command grep -qE "$re"; then
      echo "$pid"
      return 0
    fi
    pid=$(proc_ppid "$pid")
  done
  return 1
}

# Identify which agent fired this hook.
# Grok CLI also loads ~/.claude/settings.json hooks (its "Claude Code compatibility"
# scope, always active, no trust prompt) so it fires this script too. Grok injects
# GROK_* env vars into every hook; Claude Code does not.
if [ -n "$GROK_SESSION_ID" ]; then
  HOOK_SOURCE="grok"
  HOOK_TITLE="Grok CLI"
  HOOK_SESSION="$GROK_SESSION_ID"
  HOOK_PROC_RE="^grok$"
elif [ -n "$STDIN_SESSION_ID" ] || [ -n "$CLAUDE_PROJECT_DIR" ]; then
  HOOK_SOURCE="claude"
  HOOK_TITLE="Claude Code"
  HOOK_SESSION="$STDIN_SESSION_ID"
  HOOK_PROC_RE="^claude$"
else
  HOOK_SOURCE="unknown"
  HOOK_TITLE="Agent"
  HOOK_SESSION=""
  HOOK_PROC_RE="^(claude|grok)$"
fi
HOOK_AGENT_PID=$(find_agent_pid "$HOOK_PROC_RE")
debug_msg "Hook source: '$HOOK_SOURCE' session: '$HOOK_SESSION' proc: '$HOOK_PROC_RE' agent pid: '$HOOK_AGENT_PID'"

# Append one line per invocation so unexplained popups can be traced to a session.
# Override the path with NOTIFY_LOG, or set NOTIFY_LOG=/dev/null to disable.
NOTIFY_LOG="${NOTIFY_LOG:-$HOME/tmp/claude-logs/claude-input-notify.log}"
mkdir -p "$(command dirname "$NOTIFY_LOG")" 2>/dev/null
printf '%s src=%-7s agent_pid=%s event=%s type=%s session=%s cwd=%s msg=%s\n  raw=%s\n' \
  "$(iso_now)" "$HOOK_SOURCE" "${HOOK_AGENT_PID:-none}" \
  "${STDIN_EVENT:-none}" "${STDIN_NOTIFY_TYPE:-none}" \
  "${HOOK_SESSION:-none}" "${STDIN_CWD:-none}" "${STDIN_MESSAGE:-none}" \
  "$(echo "$STDIN_DATA" | command tr -d '\n' | command cut -c1-600)" \
  >>"$NOTIFY_LOG" 2>/dev/null

# Skip the popup for sources listed in NOTIFY_SKIP_SOURCES (comma-separated),
# e.g. NOTIFY_SKIP_SOURCES=grok to silence Grok while keeping Claude notifications.
if [ -n "$NOTIFY_SKIP_SOURCES" ] &&
  echo ",$NOTIFY_SKIP_SOURCES," | command grep -q ",$HOOK_SOURCE,"; then
  debug_msg "Source '$HOOK_SOURCE' is in NOTIFY_SKIP_SOURCES, skipping notification"
  echo "Source '$HOOK_SOURCE' suppressed, skipping notification"
  exit 0
fi

# Grok fires Notification for every background task completion (task_complete)
# while subagents still run. Only surface the dialog when the user must act
# (permission / elicitation) or when the turn is fully idle (idle_prompt).
# Override with NOTIFY_GROK_TYPES (comma-separated allowlist), e.g.
# NOTIFY_GROK_TYPES=permission_prompt,idle_prompt,elicitation_dialog
if [ "$HOOK_SOURCE" = "grok" ]; then
  GROK_NOTIFY_ALLOW="${NOTIFY_GROK_TYPES:-permission_prompt,idle_prompt,elicitation_dialog}"
  if [ -z "$STDIN_NOTIFY_TYPE" ]; then
    debug_msg "Grok notification missing type, skipping notification"
    echo "Grok notification missing type, skipping notification"
    exit 0
  fi
  if ! echo ",$GROK_NOTIFY_ALLOW," | command grep -q ",$STDIN_NOTIFY_TYPE,"; then
    debug_msg "Grok type '$STDIN_NOTIFY_TYPE' not in allowlist ($GROK_NOTIFY_ALLOW), skipping"
    echo "Grok type '$STDIN_NOTIFY_TYPE' skipped (not user-input/idle)"
    exit 0
  fi
  debug_msg "Grok type '$STDIN_NOTIFY_TYPE' allowed"
fi

# Get terminal window ID from first argument or try to detect it
TERMINAL_ID="$1"
TERMINAL_PID=""
TERMINAL_APP=""
debug_msg "Initial TERMINAL_ID from arg: '$TERMINAL_ID'"

if is_darwin; then
  TERMINAL_PID=$(find_macos_terminal_pid "${HOOK_AGENT_PID:-$$}")
  debug_msg "macOS terminal pid walk: '$TERMINAL_PID'"
  if [ -n "$TERMINAL_PID" ]; then
    TERMINAL_APP=$(macos_app_name_for_pid "$TERMINAL_PID") || true
  fi
  if [ -z "$TERMINAL_APP" ] && [ -n "${SUPACODE_SOCKET_PATH:-}" ]; then
    TERMINAL_APP="Supacode"
  fi
  debug_msg "macOS terminal app: '$TERMINAL_APP'"
  echo "Found terminal app: ${TERMINAL_APP:-none} pid: ${TERMINAL_PID:-none}"
else
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

    if [ -z "$TERMINAL_ID" ]; then
      TERMINAL_ID=$(xdotool search --onlyvisible --class "dev.warp.Warp" 2>/dev/null | head -n1)
      debug_msg "Method 1 - xdotool search for dev.warp.Warp: '$TERMINAL_ID'"
    fi

    if [ -z "$TERMINAL_ID" ]; then
      TERMINAL_ID=$(xdotool search --onlyvisible --class "warp" 2>/dev/null | head -n1)
      debug_msg "Method 1 - xdotool search for warp: '$TERMINAL_ID'"
    fi

    # Method 2: If not found, try wmctrl to list all windows and find terminal
    if [ -z "$TERMINAL_ID" ]; then
      # Get list of all windows with their class names
      # Use kitty\.kitty to match main kitty window, not kitty-panel
      TERMINAL_INFO=$(wmctrl -lx 2>/dev/null | grep -i -E 'kitty\.kitty|gnome-terminal|terminal\.Terminal|xfce4-terminal|mate-terminal|dev\.warp\.Warp|warp\.warp' | head -n1)
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
          if echo "$FULL_WM_CLASS" | grep -E '"kitty", "kitty"|"Kitty", "Kitty"|"gnome-terminal"|"Gnome-terminal"|"xfce4-terminal"|"Xfce4-terminal"|"mate-terminal"|"Mate-terminal"|"Terminal"|"terminal"|"dev.warp.Warp"|"warp", "warp"|"Warp", "Warp"' > /dev/null 2>&1; then
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
fi

# Skip the popup when the user is already in the agent terminal.
if [ "$TEST_MODE" -eq 0 ]; then
  if is_darwin; then
    FRONTMOST_APP=$(macos_frontmost_name) || true
    debug_msg "macOS frontmost app: '$FRONTMOST_APP' terminal app: '$TERMINAL_APP'"
    if [ -n "$FRONTMOST_APP" ] && [ -n "$TERMINAL_APP" ] && names_equal_ci "$FRONTMOST_APP" "$TERMINAL_APP"; then
      SKIP_MACOS=1
      if [ -n "${SUPACODE_TAB_ID:-}" ] && command -v supacode >/dev/null 2>&1; then
        FOCUSED_TAB=$(command supacode tab list -f --timeout 1 2>/dev/null | command head -1)
        debug_msg "macOS focused tab: '$FOCUSED_TAB' hook tab: '$SUPACODE_TAB_ID'"
        if [ -n "$FOCUSED_TAB" ] && [ "$FOCUSED_TAB" != "$SUPACODE_TAB_ID" ]; then
          SKIP_MACOS=0
          debug_msg "Different Supacode tab focused, showing notification"
        fi
      fi
      if [ "$SKIP_MACOS" -eq 1 ]; then
        debug_msg "Already in terminal app, skipping notification"
        echo "Already in terminal app, skipping notification"
        exit 0
      fi
    fi
  else
    CURRENT_WINDOW_ID=$(xdotool getactivewindow 2>/dev/null)
    debug_msg "Current active window ID: ${CURRENT_WINDOW_ID}"
    if [ -n "$TERMINAL_ID" ] && [ -n "$CURRENT_WINDOW_ID" ] && [ "$TERMINAL_ID" = "$CURRENT_WINDOW_ID" ]; then
      debug_msg "Already in terminal window, skipping notification"
      echo "Already in terminal window, skipping notification"
      exit 0
    fi
  fi
fi

if [ "$TEST_MODE" -eq 1 ]; then
  debug_msg "Test mode enabled - showing notification regardless of current window"
fi


# Brand the popup from the hook source. Grok already sets HOOK_TITLE; use
# the Grok comet mark instead of the Claude asterisk for those fires.
if [ "$HOOK_SOURCE" = "grok" ]; then
  TEXT_COLOR_PRIMARY="$TEXT_COLOR_GROK"
  ICON_PATH="${SCRIPT_DIR}/grok-logo-64.png"
  if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH="${SCRIPT_DIR}/grok-logo.png"
  fi
else
  TEXT_COLOR_PRIMARY="$TEXT_COLOR_CLAUDE"
  ICON_PATH="${SCRIPT_DIR}/claude-logo-64.png"
  if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH="${SCRIPT_DIR}/claude-logo.png"
  fi
fi
debug_msg "Icon path: '$ICON_PATH' color: '$TEXT_COLOR_PRIMARY'"

# Prepare the notification text
NOTIFY_BODY="${STDIN_MESSAGE:-Waiting for your input...}"
NOTIFY_CWD=""
if [ -n "$STDIN_CWD" ]; then
  NOTIFY_CWD=$(basename "$STDIN_CWD")
fi

NOTIFICATION_TEXT="<span size=\"xx-large\" weight=\"bold\" foreground=\"${TEXT_COLOR_PRIMARY}\">${HOOK_TITLE}</span>\n\n"
NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"large\">━━━━━━━━━━━━━━━━━━━━━━━━━━━</span>\n\n"
NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"x-large\">✨ <b>$NOTIFY_BODY</b> ✨</span>\n\n"
if [ -n "$NOTIFY_CWD" ]; then
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"small\" foreground=\"${TEXT_COLOR_DEBUG}\">${NOTIFY_CWD}</span>\n\n"
fi
NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"medium\" style=\"italic\">Click OK to return to terminal</span>"

# Add debug info if debug mode is enabled
if [ "$DEBUG_MODE" -eq 1 ] && [ -n "$DEBUG_LOG" ]; then
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}\n\n<span size=\"small\" foreground=\"${TEXT_COLOR_DEBUG}\">────────────────────────────────</span>\n"
  NOTIFICATION_TEXT="${NOTIFICATION_TEXT}<span size=\"small\" foreground=\"${TEXT_COLOR_DEBUG}\"><tt>$(echo -e "$DEBUG_LOG")</tt></span>"
fi

# Show popup notification when the agent is waiting for user input
DIALOG_EXIT_CODE=1
if is_darwin; then
  debug_msg "Showing macOS dialog"
  MAC_DEBUG=""
  if [ "$DEBUG_MODE" -eq 1 ] && [ -n "$DEBUG_LOG" ]; then
    MAC_DEBUG=$(printf '%b' "$DEBUG_LOG")
  fi
  if show_macos_dialog "$HOOK_TITLE" "$NOTIFY_BODY" "$NOTIFY_CWD" "$ICON_PATH" "$TEXT_COLOR_PRIMARY" "$MAC_DEBUG"; then
    DIALOG_EXIT_CODE=0
  else
    DIALOG_EXIT_CODE=1
  fi
else
  IMAGE_PARAMS=""
  if [ -f "$ICON_PATH" ]; then
    IMAGE_PARAMS="--image=$ICON_PATH --image-on-top"
  fi

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
  DIALOG_EXIT_CODE=$?
fi

# Function to focus kitty internal window using remote control
focus_kitty_window() {
  local target_cwd="$1"
  # Regex matching the agent process to look for. Must reflect the hook source:
  # matching "claude" for a grok-fired notification would focus the Claude window.
  local proc_re="${2:-claude}"
  local agent_pid="$3"
  debug_msg "Attempting to focus kitty window with cwd: '$target_cwd' proc: '$proc_re' pid: '$agent_pid'"

  # Linux keeps the original /tmp/kitty-* lookup. macOS kitty often uses $TMPDIR.
  local kitty_socket="" dir
  if is_darwin; then
    if [ -n "${KITTY_LISTEN_ON:-}" ]; then
      kitty_socket="${KITTY_LISTEN_ON#unix:}"
    fi
    if [ -z "$kitty_socket" ] || [ ! -S "$kitty_socket" ]; then
      kitty_socket=""
      for dir in "${TMPDIR:-/tmp}" /tmp /var/tmp; do
        kitty_socket=$(command ls -1 "$dir"/kitty-* 2>/dev/null | command head -1)
        [ -n "$kitty_socket" ] && break
      done
    fi
  else
    kitty_socket=$(ls /tmp/kitty-* 2>/dev/null | command head -1)
  fi
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

  if ! command -v jq >/dev/null 2>&1; then
    debug_msg "jq not available, cannot match kitty windows"
    return 1
  fi

  # Match on the basename of the executable so a path such as ~/.grok/... in an
  # unrelated argument cannot masquerade as the agent process. Scans every OS
  # window, not just the first.
  local jq_select='def agent($re):
      select(any(.foreground_processes[]?;
                 (.cmdline[0] // "") | split("/") | last | test($re; "i")));
    .[].tabs[].windows[]'

  # Exact match on the PID of the agent that fired this hook. Unambiguous even
  # when two sessions of the same agent share a working directory.
  local kitty_window_id=""
  if [ -n "$agent_pid" ]; then
    kitty_window_id=$(echo "$kitty_info" | jq -r --argjson pid "$agent_pid" '
      .[].tabs[].windows[] |
      select(any(.foreground_processes[]?; .pid == $pid)) | .id' 2>/dev/null | command head -1)
    debug_msg "Kitty window ID matched by agent pid $agent_pid: '$kitty_window_id'"
  fi

  # Find window running the agent with matching cwd
  if [ -z "$kitty_window_id" ] && [ -n "$target_cwd" ]; then
    kitty_window_id=$(echo "$kitty_info" | jq -r --arg cwd "$target_cwd" --arg re "$proc_re" "
      $jq_select | agent(\$re) |
      select(any(.foreground_processes[]?; .cwd == \$cwd)) | .id" 2>/dev/null | command head -1)
    debug_msg "Kitty window ID matched by cwd: '$kitty_window_id'"
  fi

  # If no match by cwd, find any window running the agent
  if [ -z "$kitty_window_id" ]; then
    kitty_window_id=$(echo "$kitty_info" | jq -r --arg re "$proc_re" "
      $jq_select | agent(\$re) | .id" 2>/dev/null | command head -1)
    debug_msg "Kitty window ID (any $proc_re): '$kitty_window_id'"
  fi

  # Last resort: loose match anywhere in the command line, still scoped to the
  # agent that fired the hook.
  if [ -z "$kitty_window_id" ]; then
    kitty_window_id=$(echo "$kitty_info" | jq -r --arg re "$proc_re" '
      .[].tabs[].windows[] |
      select(any(.foreground_processes[]?; any(.cmdline[]?; test($re; "i")))) |
      .id' 2>/dev/null | command head -1)
    debug_msg "Kitty window ID (loose $proc_re): '$kitty_window_id'"
  fi

  if [ -n "$kitty_window_id" ]; then
    debug_msg "Focusing kitty internal window ID: $kitty_window_id"
    kitty @ --to "unix:$kitty_socket" focus-window --match "id:$kitty_window_id" 2>/dev/null
    return $?
  fi

  debug_msg "No $proc_re window found in kitty"
  return 1
}

# If OK was clicked, focus the terminal that raised this hook
if [ "$DIALOG_EXIT_CODE" -eq 0 ]; then
  if is_darwin; then
    debug_msg "Attempting to focus macOS terminal app='$TERMINAL_APP' pid='$TERMINAL_PID'"
    if focus_macos_terminal "$TERMINAL_PID" "$TERMINAL_APP"; then
      debug_msg "macOS focus succeeded"
    else
      debug_msg "macOS focus failed"
    fi
    focus_kitty_window "$STDIN_CWD" "$HOOK_PROC_RE" "$HOOK_AGENT_PID" || true
  elif [ -n "$TERMINAL_ID" ]; then
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
        elif wmctrl -xa "dev.warp.Warp" 2>/dev/null; then
          debug_msg "wmctrl -xa dev.warp.Warp succeeded"
        elif wmctrl -xa "warp" 2>/dev/null; then
          debug_msg "wmctrl -xa warp succeeded"
        else
          debug_msg "All focus methods failed"
        fi
      fi
    fi

    # For kitty: also focus the specific internal window running claude
    focus_kitty_window "$STDIN_CWD" "$HOOK_PROC_RE" "$HOOK_AGENT_PID"
  else
    debug_msg "Not focusing terminal - no TERMINAL_ID"
  fi
else
  debug_msg "Not focusing terminal - exit code: $DIALOG_EXIT_CODE, TERMINAL_ID: '$TERMINAL_ID' app: '$TERMINAL_APP'"
fi

# Exit 0 to allow normal operation to continue
exit 0
