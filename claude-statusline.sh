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
        git_info="[$branch$staged$unstaged]$submodule_info"
    fi
fi

# Build the status line with dimmed colors (without user@host, date, or time)
# Show: cwd git_info [model]
printf "\033[2;34m%s\033[0m \033[2;33m%s\033[0m \033[2;36m[%s]\033[0m" \
    "$cwd" "$git_info" "$model"
