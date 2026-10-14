#!/usr/bin/env bash
# Collect the facts for an Oh My Zsh post-update check.
# Usage: bash check.sh [OLD_REV [NEW_REV]]
# Without revisions, the range comes from the last "pull" entry in the OMZ reflog.

set -u

OMZ="${ZSH:-$HOME/.oh-my-zsh}"
REPO="$HOME/bin"
HOME_SETTINGS="$REPO/settings/osx/home"
OUR_FILES=(aliases zshrc zshprompt zshenv zprofile oh-my-zsh/custom)

section() { printf '\n===== %s\n' "$1"; }

section "1. OMZ working tree (must be empty)"
git -C "$OMZ" status --short
git -C "$OMZ" stash list

section "2. Update range"
OLD="${1:-}"
NEW="${2:-}"
if [ -z "$OLD" ]; then
  # Reflog: "<hash> pull ... Fast-forward" holds NEW; the next entry holds OLD.
  read -r NEW OLD < <(git -C "$OMZ" reflog --format='%h %gs' |
    awk '/ pull /{n=$1; getline; print n, $1; exit}')
fi
NEW="${NEW:-HEAD}"
if [ -z "$OLD" ]; then
  echo "No pull entry in the OMZ reflog. Pass OLD_REV explicitly." >&2
  exit 1
fi
echo "OLD=$OLD NEW=$NEW"
git -C "$OMZ" log -1 --format='newest upstream commit: %cd' "$NEW"
git -C "$OMZ" reflog -n 6 --date=iso
git -C "$OMZ" log --oneline "$OLD..$NEW"

section "3. Plugins in use and where they load from"
PLUGIN_REPORT=$(command zsh -i -c '
  echo "ZSH_CUSTOM=$ZSH_CUSTOM"
  for p in $plugins; do
    if [ -f "$ZSH_CUSTOM/plugins/$p/$p.plugin.zsh" ]; then echo "$p custom"
    elif [ -f "$ZSH/plugins/$p/$p.plugin.zsh" ]; then echo "$p stock"
    else echo "$p MISSING"; fi
  done' 2>/dev/null)
echo "$PLUGIN_REPORT"
STOCK_PLUGINS=$(echo "$PLUGIN_REPORT" | awk '$2=="stock"{print $1}')

section "4. Changed paths that touch us (custom/, lib/, oh-my-zsh.sh, tools/, used plugins)"
PATHS=(custom lib oh-my-zsh.sh tools)
for p in $STOCK_PLUGINS; do PATHS+=("plugins/$p"); done
git -C "$OMZ" diff --stat "$OLD" "$NEW" -- "${PATHS[@]}"

section "5. custom/example.zsh in repo vs OMZ"
diff -q "$HOME_SETTINGS/oh-my-zsh/custom/example.zsh" "$OMZ/custom/example.zsh" && echo "same"

section "6. Added or removed aliases/functions in used plugins, and clashes with ours"
PLUGIN_PATHS=()
for p in $STOCK_PLUGINS; do PLUGIN_PATHS+=("plugins/$p"); done
NAMES=$(git -C "$OMZ" diff "$OLD" "$NEW" -- "${PLUGIN_PATHS[@]}" ':(exclude)plugins/*/tests/*' |
  command grep -E '^[+-][[:space:]]*(alias[[:space:]]+[^=[:space:]]+=|function[[:space:]]+[A-Za-z0-9_-]+|[A-Za-z0-9_-]+[[:space:]]*\(\))' |
  command sed -E 's/^([+-])[[:space:]]*(alias[[:space:]]+([^=[:space:]]+)=.*|function[[:space:]]+([A-Za-z0-9_-]+).*|([A-Za-z0-9_-]+)[[:space:]]*\(\).*)$/\1 \3\4\5/' |
  sort -u)
if [ -z "$NAMES" ]; then
  echo "none"
else
  echo "$NAMES"
  echo "--- clashes in ${OUR_FILES[*]}:"
  (cd "$HOME_SETTINGS" &&
    echo "$NAMES" | awk '{print $2}' | sort -u | while read -r n; do
      command grep -rnw -- "$n" "${OUR_FILES[@]}" 2>/dev/null |
        command grep -v '^oh-my-zsh/custom/plugins/' | sed "s/^/[$n] /"
    done)
  echo "--- end of clashes"
fi

section "7. ~/bin working tree"
git -C "$REPO" status --short
echo "done"
