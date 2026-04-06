#!/bin/bash
# Move files from subdirectories (depth >= 2) into the current directory.
# If a file with the same name already exists, append _001, _002, etc.
# before the extension (or at the end if no extension).

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN — no files will be moved ==="
fi

moved=0
skipped=0

while IFS= read -r -d '' src; do
    basename="$(command basename "$src")"
    dest="./$basename"

    if [[ ! -e "$dest" ]]; then
        # No conflict — move directly
        if $DRY_RUN; then
            echo "MOVE: $src -> $dest"
        else
            command mv -- "$src" "$dest"
        fi
        ((moved++))
    else
        # Conflict — find next available _NNN suffix
        name="${basename%.*}"
        ext="${basename##*.}"

        # Handle files with no extension or dotfiles
        if [[ "$name" == "$ext" || "$name" == "" ]]; then
            ext=""
        fi

        counter=1
        while true; do
            suffix=$(printf "_%03d" "$counter")
            if [[ -n "$ext" ]]; then
                candidate="./${name}${suffix}.${ext}"
            else
                candidate="./${basename}${suffix}"
            fi

            if [[ ! -e "$candidate" ]]; then
                if $DRY_RUN; then
                    echo "MOVE: $src -> $candidate (renamed)"
                else
                    command mv -- "$src" "$candidate"
                fi
                ((moved++))
                break
            fi
            ((counter++))
        done
    fi
done < <(command find . -mindepth 2 -type f -print0)

echo "Done: $moved file(s) moved."

if ! $DRY_RUN; then
    # Remove empty subdirectories left behind
    command find . -mindepth 1 -type d -empty -delete 2>/dev/null || true
    echo "Empty subdirectories removed."
fi
