#!/bin/bash
# Keep the NoMachine ISO key as ч and ~. The laptop key is unchanged.
# See nomachine-che-tilde.c.

set -euo pipefail

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$DIR/nomachine-che-tilde.c"
BIN="$DIR/nomachine-che-tilde"

if [ -z "${DISPLAY:-}" ]; then
  export DISPLAY=:0
fi
export NOMACHINE_CHE_TILDE_MAP="$DIR/nomachine-che-tilde-map.sh"

if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
  command gcc -Wall -Wextra -O2 -o "$BIN" "$SRC" -lX11 -lXi -lXtst
fi

exec "$BIN" "$@"
