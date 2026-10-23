#!/bin/bash
# Pull ~/develop/personal/ from another machine over SSH into the same
# path on this Mac. Dry-run unless the last argument is doit.
# There is no --delete. A .rsync-filter on the source is not applied:
# this script does not pass -F or -C.
#
# Usage:
#   rsync_from.sh <host> [exclude-file] [doit]
#   rsync_from.sh user@<host> [exclude-file] [doit]
#
# <host> is the SSH destination. A bare host is sent as the local user
# name, so an SSH config User does not replace it. user@host keeps the
# user you wrote.
# [exclude-file] is an optional rsync --exclude-from list. Omit it to copy
# every directory. Homebrew rsync is required. Apple rsync rejects
# --info=progress2.

[ "$1" = -x ] && shift && set -x
set -euo pipefail

usage() {
  echo "usage: rsync_from.sh <host|user@host> [exclude-file] [doit]" >&2
  exit 2
}

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
fi

HOST="$1"
shift

EXCLUDE=""
MODE=""
if [ "${1:-}" = "doit" ]; then
  MODE="doit"
  shift
elif [ "${1:-}" != "" ]; then
  EXCLUDE="$1"
  shift
  if [ "${1:-}" = "doit" ]; then
    MODE="doit"
    shift
  fi
fi

if [ $# -ne 0 ]; then
  usage
fi

case "$HOST" in
  *@*) ;;
  *) HOST="$(id -un)@${HOST}" ;;
esac

RSYNC="${RSYNC:-/opt/homebrew/bin/rsync}"
if [ ! -x "$RSYNC" ]; then
  echo "need an executable rsync (default /opt/homebrew/bin/rsync)" >&2
  exit 1
fi

DEST="${HOME}/develop/personal/"
SRC="${HOST}:~/develop/personal/"

ARGS=(
  -ah
  --info=progress2
  --partial
)

echo "source: ${SRC}"
echo "dest:   ${DEST}"

if [ "$EXCLUDE" != "" ]; then
  if [ ! -f "$EXCLUDE" ]; then
    echo "missing exclude file: ${EXCLUDE}" >&2
    exit 1
  fi
  ARGS+=(--exclude-from="$EXCLUDE")
  echo "exclude: ${EXCLUDE}"
  echo "skipped patterns:"
  command grep -E -v '^[[:space:]]*($|#|;)' "$EXCLUDE" || true
else
  echo "exclude: none"
fi

echo "remote .rsync-filter: ignored"

if [ "$MODE" != "doit" ]; then
  echo "dry-run. Pass doit to copy."
  ARGS+=(-n --stats)
  exec "$RSYNC" "${ARGS[@]}" "$SRC" "$DEST"
fi

echo "copying. The Mac stays awake until rsync exits."
exec caffeinate -i "$RSYNC" "${ARGS[@]}" "$SRC" "$DEST"
