#!/bin/zsh
# Remove fix-cyr and undo what install.sh set up for its mode (Globe or Caps Lock).
LABEL=com.mony.fixcyr
PLIST=~/Library/LaunchAgents/$LABEL.plist
KARABINER_JSON=~/.config/karabiner/karabiner.json

[[ -f $PLIST ]] || { echo "fix-cyr is not installed."; exit 0; }
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null
if grep -q '<string>f18</string>' "$PLIST"; then
  if grep -q -- '--hidutil-capslock' "$PLIST"; then
    hidutil property --set '{"UserKeyMapping":[]}' > /dev/null
  elif [[ -f $KARABINER_JSON ]]; then
    jq '(.profiles[] | select(.selected == true) | .simple_modifications) |=
          ((. // []) | map(select(.from.key_code != "caps_lock" or .to != [{"key_code": "f18"}])))' \
      "$KARABINER_JSON" > "$KARABINER_JSON.tmp" \
      && cat "$KARABINER_JSON.tmp" > "$KARABINER_JSON" && rm "$KARABINER_JSON.tmp"  # write through a symlink
  fi
  echo "Uninstalled. Caps Lock is Caps Lock again."
else
  defaults write com.apple.HIToolbox AppleFnUsageType -int 1
  echo "Uninstalled. Globe switches input source again (may need logout)."
fi
rm -f "$PLIST"
