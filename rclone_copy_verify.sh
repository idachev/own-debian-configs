#!/bin/bash
# Copy a local directory to an rclone remote, then verify it with rclone check.
#
# Usage: rclone_copy_verify.sh <src_dir> <remote:path> [extra rclone flags...]
#
# The copy only uploads new or changed files, so a failed or stopped run can be
# started again with the same arguments. Logs go to ./tmp/claude-logs/ (or
# $LOG_DIR) with a timestamp in the file name.
#
# Default flags suit Google Drive, which limits how many files per second one
# user can create. Override them with extra flags, e.g. --transfers 16.
#
# Example:
#   rclone_copy_verify.sh ./books-zips my-shared-drive:books

set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

src=$1
dst=$2
shift 2

if [ ! -d "$src" ]; then
  echo "Not a directory: $src" >&2
  exit 1
fi

log_dir=${LOG_DIR:-./tmp/claude-logs}
mkdir -p "$log_dir"
stamp=$(date +%Y%m%d-%H%M%S)
copy_log="$log_dir/rclone-copy-$stamp.log"
check_log="$log_dir/rclone-check-$stamp.log"

echo "copy  $src -> $dst"
echo "log   $copy_log"
rclone copy "$src" "$dst" \
  --transfers 8 --checkers 16 --tpslimit 8 \
  --exclude .DS_Store --exclude '*.part' \
  --stats 1m --stats-one-line --log-level INFO \
  --log-file "$copy_log" "$@"

echo "check $src <-> $dst"
echo "log   $check_log"
rclone check "$src" "$dst" --one-way \
  --exclude .DS_Store --exclude '*.part' \
  --log-file "$check_log" "$@"

command tail -n 3 "$check_log"
