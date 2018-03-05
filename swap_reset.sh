#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  echo "Requires sudo to start me.";
  exit 1;
fi

echo "Switching swap off..."
swapoff -a

echo "Switching swap on..."
swapon -a

echo "Done."
