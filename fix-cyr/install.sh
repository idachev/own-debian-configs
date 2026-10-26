#!/bin/zsh
# Build fix-cyr and install it as a login LaunchAgent.
#   ./install.sh                         Globe toggles ABC <-> Bulgarian-Phonetic; Globe set to "Do Nothing"
#   ./install.sh --capslock              Caps Lock toggles instead (remapped to F18 via Karabiner, else hidutil)
#   --layout-a ID / --layout-b ID        input sources to toggle between (any mode)
set -e
cd "${0:A:h}"
LABEL=com.mony.fixcyr
PLIST=~/Library/LaunchAgents/$LABEL.plist
BIN="$PWD/bin/fix-cyr"
KARABINER_CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
KARABINER_JSON=~/.config/karabiner/karabiner.json

ARGS=()
CAPSLOCK=0
while (( $# )); do
  case $1 in
    --capslock) CAPSLOCK=1 ;;
    --layout-a|--layout-b)
      [[ -n $2 && $2 != --* ]] || { echo "$1 needs an input source ID"; exit 2; }
      ARGS+=($1 $2); shift ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
  shift
done

if (( CAPSLOCK )) && [[ -x $KARABINER_CLI ]]; then
  [[ -f $KARABINER_JSON ]] || { echo "Karabiner has no $KARABINER_JSON yet: open Karabiner-Elements once, then rerun"; exit 1; }
  command -v jq > /dev/null || { echo "jq is required to edit $KARABINER_JSON"; exit 1; }
fi

# Undo the previous install first, so switching between Globe and Caps Lock mode leaves nothing behind
[[ -f $PLIST ]] && ./uninstall.sh

mkdir -p bin
swiftc -O main.swift -o "$BIN"
codesign -s - -f -i "$LABEL" "$BIN"

if (( CAPSLOCK )); then
  ARGS+=(--key f18)
  if [[ -x $KARABINER_CLI ]]; then
    # Karabiner seizes the keyboard, so hidutil would not see Caps Lock: add caps_lock -> f18 there
    cp "$KARABINER_JSON" "$KARABINER_JSON.fix-cyr-backup-$(date +%Y%m%d-%H%M%S)"
    jq '(.profiles[] | select(.selected == true) | .simple_modifications) |=
          ((. // []) | map(select(.from.key_code != "caps_lock"))
           + [{"from": {"key_code": "caps_lock"}, "to": [{"key_code": "f18"}]}])' \
      "$KARABINER_JSON" > "$KARABINER_JSON.tmp"
    cat "$KARABINER_JSON.tmp" > "$KARABINER_JSON" && rm "$KARABINER_JSON.tmp"  # write through a symlink
    echo "Karabiner: caps_lock -> f18 added to the selected profile (backup next to karabiner.json)"
  else
    ARGS+=(--hidutil-capslock)
  fi
else
  # Globe key: Do Nothing (fix-cyr does the switching)
  defaults write com.apple.HIToolbox AppleFnUsageType -int 0
fi

PROGRAM_ARGS="<string>$BIN</string>"
for a in $ARGS; do PROGRAM_ARGS+="<string>$a</string>"; done

mkdir -p "${PLIST:h}"  # a fresh account has no ~/Library/LaunchAgents yet
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>$PROGRAM_ARGS</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardErrorPath</key><string>/tmp/fix-cyr.log</string>
</dict>
</plist>
EOF

launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "Installed. If the key does nothing: Privacy & Security -> Input Monitoring -> enable $BIN"
