#!/bin/bash
# Put ч and ~ on an unused keycode. The laptop <> key is not changed.
# Cinnamon may reload the keymap; the daemon calls this again when that happens.

set -euo pipefail

if [ -z "${DISPLAY:-}" ]; then
  export DISPLAY=:0
fi

cache="${XDG_CACHE_HOME:-$HOME/.cache}"
command mkdir -p "$cache"
out="$cache/nomachine-che-tilde.xkb"
log="$cache/nomachine-che-tilde.log"

if ! command xkbcomp "$DISPLAY" "$out" >"$cache/nomachine-che-tilde-xkbcomp.err" 2>&1; then
  command cat "$cache/nomachine-che-tilde-xkbcomp.err" >>"$log"
  exit 1
fi

python3 - "$out" << 'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
if "key <I248>" in text:
    sys.exit(0)
anchor = "    key <I249>"
block = """    key <I248> {
        type= "TWO_LEVEL",
        symbols[Group1]= [ Cyrillic_che, asciitilde ]
    };
"""
if anchor not in text:
    sys.exit("nomachine-che-tilde-map: key <I249> is missing")
path.write_text(text.replace(anchor, block + anchor, 1))
PY

if ! command xkbcomp "$out" "$DISPLAY" >"$cache/nomachine-che-tilde-xkbcomp.err" 2>&1; then
  command cat "$cache/nomachine-che-tilde-xkbcomp.err" >>"$log"
  exit 1
fi
