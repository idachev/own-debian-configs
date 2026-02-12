#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bash_lib.sh"

REMOTE_NAME="gdrive"

usage() {
  echo "Usage:"
  echo "  $(basename "$0") [--remote <name>] <drive_folder> <local_mount_point>"
  echo "  $(basename "$0") --unmount <local_mount_point>"
  echo ""
  echo "Mount a Google Drive folder locally using rclone."
  echo "Runs in the foreground - press Ctrl+C to unmount."
  echo ""
  echo "Options:"
  echo "  --remote <name>  Rclone remote name (default: gdrive)"
  echo "  --unmount        Unmount the specified mount point"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") my-folder /tmp/gdrive-mount"
  echo "  $(basename "$0") / /tmp/gdrive-mount                           # mount entire Drive"
  echo "  $(basename "$0") --remote gdrive-igd-bg-solutions / /tmp/igd   # use different remote"
  echo "  $(basename "$0") --unmount /tmp/gdrive-mount"
  exit 1
}

do_unmount() {
  local mount_point="$1"
  check_not_empty "${mount_point}" "local_mount_point" || exit 1

  if mountpoint -q "${mount_point}" 2>/dev/null; then
    echo "Unmounting ${mount_point}..."
    fusermount -u "${mount_point}"
    echo "Unmounted successfully."
  else
    echo "${mount_point} is not a mount point."
    exit 1
  fi
}

cleanup() {
  echo ""
  echo "Caught signal, unmounting ${LOCAL_MOUNT_POINT}..."
  fusermount -u "${LOCAL_MOUNT_POINT}" 2>/dev/null || true
  echo "Unmounted. Exiting."
}

# Handle --unmount mode
if [[ "${1:-}" == "--unmount" ]]; then
  [[ -z "${2:-}" ]] && usage
  do_unmount "$2"
  exit 0
fi

# Parse --remote option
if [[ "${1:-}" == "--remote" ]]; then
  [[ -z "${2:-}" ]] && usage
  REMOTE_NAME="$2"
  shift 2
fi

# Mount mode: require two arguments
[[ $# -lt 2 ]] && usage

DRIVE_FOLDER="$1"
LOCAL_MOUNT_POINT="$2"

check_not_empty "${LOCAL_MOUNT_POINT}" "local_mount_point" || exit 1

if ! command -v rclone &>/dev/null; then
  echo "Error: rclone is not installed." >&2
  exit 1
fi

# Create mount point if it doesn't exist
if [[ ! -d "${LOCAL_MOUNT_POINT}" ]]; then
  echo "Creating mount point directory: ${LOCAL_MOUNT_POINT}"
  mkdir -p "${LOCAL_MOUNT_POINT}"
fi

trap cleanup SIGINT SIGTERM

echo "Mounting ${REMOTE_NAME}:${DRIVE_FOLDER} at ${LOCAL_MOUNT_POINT}"
echo "Press Ctrl+C to unmount and exit."
echo ""

rclone mount "${REMOTE_NAME}:${DRIVE_FOLDER}" "${LOCAL_MOUNT_POINT}" \
  --vfs-cache-mode full \
  --vfs-cache-max-age 1h \
  --dir-cache-time 5m \
  --poll-interval 15s \
  --allow-other
