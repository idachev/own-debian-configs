#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract values from JSON
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')

# Replace home directory with just ~
cwd="${cwd/#$HOME/\~}"

# Get git branch info if in a git repo
git_info=""
if git --no-optional-locks rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks rev-parse --short HEAD 2>/dev/null)

    # Check for staged/unstaged changes
    staged=""
    unstaged=""

    if ! git --no-optional-locks diff --cached --quiet 2>/dev/null; then
        staged="●"
    fi

    if ! git --no-optional-locks diff --quiet 2>/dev/null; then
        unstaged="●"
    fi

    # Count untracked files
    untracked=""
    untracked_count=$(git --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l)
    if [ "$untracked_count" -gt 0 ]; then
        untracked="?${untracked_count}"
    fi

    # Ahead/behind vs upstream
    ahead_behind=""
    if upstream=$(git --no-optional-locks rev-parse --abbrev-ref '@{u}' 2>/dev/null); then
        counts=$(git --no-optional-locks rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null)
        if [ -n "$counts" ]; then
            behind=$(echo "$counts" | awk '{print $1}')
            ahead=$(echo "$counts" | awk '{print $2}')
            [ "$ahead" != "0" ] && ahead_behind="${ahead_behind}↑${ahead}"
            [ "$behind" != "0" ] && ahead_behind="${ahead_behind}↓${behind}"
        fi
    fi

    # Build detailed submodule information
    submodule_info=""
    if [ -f .gitmodules ]; then
        # Get list of submodules
        submodules=$(git --no-optional-locks config --file .gitmodules --get-regexp path | awk '{ print $2 }')

        if [ -n "$submodules" ]; then
            submodule_parts=()

            while IFS= read -r sm_path; do
                if [ -n "$sm_path" ] && [ -d "$sm_path" ]; then
                    # Get submodule name (last part of path)
                    sm_name=$(basename "$sm_path")

                    # Get submodule branch
                    sm_branch=$(cd "$sm_path" 2>/dev/null && git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || echo "detached")

                    # Check submodule status (clean/dirty)
                    sm_status="✓"
                    if [ -d "$sm_path/.git" ] || [ -f "$sm_path/.git" ]; then
                        # Check for uncommitted changes in submodule
                        if ! (cd "$sm_path" 2>/dev/null && git --no-optional-locks diff --quiet 2>/dev/null && git --no-optional-locks diff --cached --quiet 2>/dev/null); then
                            sm_status="●"
                        fi
                    fi

                    # Add to submodule parts
                    submodule_parts+=("$sm_name:$sm_branch$sm_status")
                fi
            done <<< "$submodules"

            # Join all submodule info
            if [ ${#submodule_parts[@]} -gt 0 ]; then
                submodule_info=" {$(IFS=,; echo "${submodule_parts[*]}")}"
            fi
        fi
    fi

    if [ -n "$branch" ]; then
        git_info="[$branch$staged$unstaged$untracked$ahead_behind]$submodule_info"
    fi
fi

# Context window as a 10-block bar (color-coded: green <60, yellow 60-85, red >=85)
ctx_info=""
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$ctx_pct" ] && [ "$ctx_pct" != "null" ]; then
    ctx_int=$(printf "%.0f" "$ctx_pct")
    filled=$(( (ctx_int + 5) / 10 ))
    [ "$filled" -gt 10 ] && filled=10
    [ "$filled" -lt 0 ] && filled=0
    empty=$(( 10 - filled ))
    if [ "$ctx_int" -ge 85 ]; then
        ctx_color="\033[1;31m"
    elif [ "$ctx_int" -ge 60 ]; then
        ctx_color="\033[1;33m"
    else
        ctx_color="\033[1;32m"
    fi
    bar_filled=""
    bar_empty=""
    [ "$filled" -gt 0 ] && bar_filled=$(printf '▰%.0s' $(seq 1 $filled))
    [ "$empty" -gt 0 ] && bar_empty=$(printf '▱%.0s' $(seq 1 $empty))
    ctx_info=$(printf " ${ctx_color}%s\033[2;37m%s${ctx_color}(%d%%)\033[0m" "$bar_filled" "$bar_empty" "$ctx_int")
fi

# Session cost in USD
cost_info=""
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$cost_usd" ] && [ "$cost_usd" != "null" ]; then
    cost_info=$(printf " \033[2;35m\$%.2f\033[0m" "$cost_usd")
fi

# Lines added/removed this session
lines_info=""
added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
if [ "$added" != "0" ] || [ "$removed" != "0" ]; then
    lines_info=$(printf " \033[2;32m+%s\033[0m/\033[2;31m-%s\033[0m" "$added" "$removed")
fi

# Build the status line with dimmed colors (without user@host, date, or time)
# Show: cwd git_info [model] ctx cost lines
printf "\033[2;34m%s\033[0m \033[2;33m%s\033[0m \033[2;36m[%s]\033[0m%b%b%b" \
    "$cwd" "$git_info" "$model" "$ctx_info" "$cost_info" "$lines_info"
