#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  echo "Requires sudo to start me.";
  exit 1;
fi

DEVICE="Virtual1"

xrandr --newmode "1920x1080"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync

xrandr --addmode "${DEVICE}" 1920x1080

xrandr --output "${DEVICE}" --mode 1920x1080

