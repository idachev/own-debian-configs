#!/bin/sh

# For firefox install FlashGot and add as cmd option this:
# [URL] -d [FOLDER]

NOW=$(date +"%Y-%m-%d_%H:%M:%S")
TMP_LOG="$(mktemp /tmp/aria2c_flashgot_log_$NOW.XXXXXXXXXX)"

unset http_proxy
unset https_proxy

glogg $TMP_LOG&

ARIA2C_OPTIONS="--file-allocation=falloc --check-certificate=false --timeout=600"

# No progress info in log use only for debug
#aria2c $ARIA2C_OPTIONS -l $TMP_LOG --log-level=info $@ &

while true; do
  echo -e "aria2c $ARIA2C_OPTIONS $@\n" >> $TMP_LOG
  aria2c $ARIA2C_OPTIONS $@ >> $TMP_LOG 2>&1
  err=$?
  if [ "$err" = "0" ]; then
    break
  fi
  echo -e "Error in the exit code: $err restarting...\n\n\n\n\n" >> $TMP_LOG
  sleep 10
done

