#!/bin/sh
# Put this Mac to sleep with a lid close while "never sleep" is on.
#
# Setup (once, AC and battery, lid close included, display timer unchanged):
#   sudo pmset -a sleep 0 disablesleep 1
#
# While that is on, the lid does not sleep the machine. This script clears
# disablesleep and tells you to close the lid. It puts sleep 0 and
# disablesleep 1 back only when the lid is open again. For the sleep it
# also turns off powernap, tcpkeepalive and womp; their old values are
# saved and mac_force_unsleep.sh puts them back on exit. A dark wake
# (DHCP, Power Nap, TCP keepalive) keeps the lid closed, so the machine
# goes back to sleep. pmset sleepnow is not used: it was aborted after
# about 3 s on this machine, while the lid close sleeps it reliably.
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

state=/var/db/mac_force_sleep.state
case $0 in
  */*) unsleep=${0%/*}/mac_force_unsleep.sh ;;
  *) unsleep=./mac_force_unsleep.sh ;;
esac

restore() {
  rc=$?
  # A second Ctrl-C must not abort pmset; children inherit the ignore.
  trap '' INT TERM HUP
  if [ -f "$unsleep" ]; then
    /bin/sh "$unsleep" || rc=1
  else
    echo "Липсва $unsleep. Връщам само sleep 0 и disablesleep 1." >&2
    /usr/bin/pmset -a sleep 0 disablesleep 1 || true
    rc=1
  fi
  exit "$rc"
}

# Saves powernap, tcpkeepalive and womp for battery (b) and AC (c).
save_state() {
  /usr/bin/pmset -g custom | /usr/bin/awk '
    /^Battery Power:/ { src = "b"; next }
    /^AC Power:/ { src = "c"; next }
    src != "" && ($1 == "powernap" || $1 == "tcpkeepalive" || $1 == "womp") {
      print src, $1, $2
    }' > "$state.tmp"
  # No pipefail in sh: a failed pmset leaves an empty or short file.
  if [ "$(/usr/bin/wc -l < "$state.tmp")" -ne 6 ]; then
    /bin/rm -f "$state.tmp"
    echo "Не прочетох powernap, tcpkeepalive и womp от pmset. Спирам." >&2
    exit 1
  fi
  /bin/mv "$state.tmp" "$state"
}

# Prints Yes or No.
clamshell() {
  /usr/sbin/ioreg -r -k "$1" -d 1 | /usr/bin/sed -n "s/.*\"$1\" = //p" |
    /usr/bin/head -n 1
}

trap restore EXIT
trap 'exit 130' INT TERM HUP

if [ "$(clamshell AppleClamshellCausesSleep)" != Yes ]; then
  echo "Затвореният капак сега не приспива машината (външен дисплей?)." >&2
  echo "Махни външния дисплей и пусни пак." >&2
  exit 1
fi

if [ "$(clamshell AppleClamshellState)" != No ]; then
  echo "Капакът вече е затворен. Отвори го и пусни пак." >&2
  exit 1
fi

# Without it the saved powernap, tcpkeepalive and womp do not come back.
if [ ! -f "$unsleep" ]; then
  echo "Липсва $unsleep. Спирам, преди да пипна нещо." >&2
  exit 1
fi

# An old state file means the last run did not restore. Its values are the
# real ones; the current ones may be the zeros set below.
if [ -f "$state" ]; then
  echo "Има запазено състояние от минал път. Пазя него."
else
  save_state
fi

/usr/bin/pmset -a disablesleep 0
# Power Nap, TCP keepalive and Wake on LAN cause dark wakes. Sleep works
# without this step, so a refusal (an unsupported key) does not stop it.
/usr/bin/pmset -a powernap 0 tcpkeepalive 0 womp 0 >/dev/null 2>&1 ||
  echo "Power Nap, TCP keepalive или Wake on LAN не се изключиха." >&2
echo "Затвори капака сега. Имаш 60 s."

# A clock jump means the machine slept. Watch for it in both loops:
# the machine can sleep and wake again before the lid check sees Yes.
slept=0
prev=$(/bin/date +%s)
i=0
while [ "$(clamshell AppleClamshellState)" != Yes ]; do
  if [ "$i" -ge 60 ]; then
    echo "Капакът не се затвори за 60 s. Настройката „без сън“ се връща." >&2
    exit 1
  fi
  /bin/sleep 1
  now=$(/bin/date +%s)
  if [ $((now - prev)) -gt 5 ]; then
    slept=1
    break
  fi
  prev=$now
  i=$((i + 1))
done

# Lid closed. Wait for it to open. Only an explicit No counts: an empty
# ioreg read must not restore "never sleep" with the lid still closed.
while [ "$(clamshell AppleClamshellState)" != No ]; do
  /bin/sleep 2
  now=$(/bin/date +%s)
  if [ $((now - prev)) -gt 5 ]; then
    slept=1
  fi
  prev=$now
done
# The machine can sleep between the last prev and the lid check.
now=$(/bin/date +%s)
if [ $((now - prev)) -gt 5 ]; then
  slept=1
fi

if [ "$slept" -eq 1 ]; then
  echo "Машината спа. Настройката „без сън“ се връща."
else
  echo "Капакът се отвори, но машината не заспа. Настройката „без сън“ се връща." >&2
  exit 1
fi
