#!/bin/sh
# Force this Mac to sleep while "never sleep" is on.
#
# Setup (once, AC and battery, lid close included, display timer unchanged):
#   sudo pmset -a sleep 0 disablesleep 1
#
# While that is on, the Apple menu Sleep item does nothing and the lid
# does not sleep the machine. This script clears disablesleep, requests
# sleep, and waits until the clock jumps (the machine actually slept).
# pmset sleepnow returns as soon as the request is accepted, so restoring
# disablesleep before that jump can cancel the sleep.
# After wake it puts sleep 0 and disablesleep 1 back.
# It does not change displaysleep.

set -eu

if [ "$(uname -s)" != Darwin ]; then
  echo "Този скрипт е само за macOS." >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  case $0 in
    */*) script=$0 ;;
    *) script=$(command -v "$0") || exit 1 ;;
  esac
  exec sudo /bin/sh "$script" "$@"
fi

restore() {
  /usr/bin/pmset -a sleep 0 disablesleep 1
}

trap restore EXIT

/usr/bin/pmset -a disablesleep 0
echo "Приспивам. След събуждане настройката „без сън“ се връща."
before=$(/bin/date +%s)
if ! /usr/bin/pmset sleepnow; then
  echo "macOS отказа съня. Настройката „без сън“ се връща." >&2
  exit 1
fi

# sleepnow may return at once, or only after wake. A clock jump means we slept.
prev=$(/bin/date +%s)
if [ $((prev - before)) -gt 5 ]; then
  exit 0
fi
i=0
while [ "$i" -lt 60 ]; do
  /bin/sleep 1
  now=$(/bin/date +%s)
  if [ $((now - prev)) -gt 5 ]; then
    exit 0
  fi
  prev=$now
  i=$((i + 1))
done
echo "Машината не заспа за 60 s. Настройката „без сън“ се връща." >&2
exit 1
