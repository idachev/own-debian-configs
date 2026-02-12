#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${SCRIPT_DIR}/rclone_mount_gdrive.sh" --remote gdrive-igd-bg-solutions / /home/idachev/storage_b/gdrive-igd-bg-solutions
