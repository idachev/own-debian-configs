#!/bin/sh
# Put back the "never sleep" state after mac_force_sleep.sh and check it.
#
# mac_force_sleep.sh saves powernap, tcpkeepalive and womp for battery
# and AC to $state before it turns them off. This script writes the
# saved values back, sets sleep 0 and disablesleep 1, removes $state and
# checks that pmset now shows all of it. Without $state it sets only
# sleep 0 and disablesleep 1. mac_force_sleep.sh runs it on exit; you can
# also run it by hand when you are not sure the state is right.

set -eu

state=/var/db/mac_force_sleep.state

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

trap '' INT TERM HUP

# Prints "<b|c> <key> <value>" for each key, from pmset -g custom.
current() {
  /usr/bin/pmset -g custom | /usr/bin/awk '
    /^Battery Power:/ { src = "b"; next }
    /^AC Power:/ { src = "c"; next }
    src != "" && ($1 == "powernap" || $1 == "tcpkeepalive" ||
                  $1 == "womp" || $1 == "sleep") {
      print src, $1, $2
    }'
}

if [ -f "$state" ]; then
  for src in b c; do
    args=$(/usr/bin/awk -v s="$src" '
      $1 == s && $2 ~ /^(powernap|tcpkeepalive|womp)$/ && $3 ~ /^[0-9]+$/ {
        printf "%s %s ", $2, $3
      }' "$state")
    if [ -n "$args" ]; then
      # shellcheck disable=SC2086 # args is "key value" pairs.
      # A failure here shows up in the check below.
      /usr/bin/pmset -"$src" $args >/dev/null 2>&1 || true
    fi
  done
fi
/usr/bin/pmset -a sleep 0 disablesleep 1 || true

fail=0
now=$(current)

for src in b c; do
  case $src in
    b) label="батерия" ;;
    c) label="ток" ;;
  esac
  value=$(echo "$now" | /usr/bin/awk -v s="$src" '$1 == s && $2 == "sleep" { print $3 }')
  if [ "$value" != 0 ]; then
    echo "ГРЕШКА: sleep на $label е ${value:-липсва}, трябва 0." >&2
    fail=1
  fi
done

if ! /usr/bin/pmset -g | /usr/bin/grep -Eq '^[[:space:]]*SleepDisabled[[:space:]]+1'; then
  echo "ГРЕШКА: SleepDisabled не е 1." >&2
  fail=1
fi

if [ -f "$state" ]; then
  checked=0
  while read -r src key want; do
    case $key in powernap | tcpkeepalive | womp) ;; *) continue ;; esac
    checked=$((checked + 1))
    got=$(echo "$now" | /usr/bin/awk -v s="$src" -v k="$key" '$1 == s && $2 == k { print $3 }')
    if [ "$got" != "$want" ]; then
      echo "ГРЕШКА: $key ($src) е ${got:-липсва}, трябва $want." >&2
      fail=1
    fi
  done < "$state"
  if [ "$checked" -eq 0 ]; then
    echo "ГРЕШКА: $state няма запазени стойности." >&2
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "Състоянието не е наред. Запазените стойности са в $state." >&2
  exit 1
fi

/bin/rm -f "$state"
echo "Всичко е наред: sleep 0, SleepDisabled 1."
echo "$now" | /usr/bin/awk '$2 != "sleep" {
  printf "  %s %s %s\n", ($1 == "b" ? "батерия" : "ток    "), $2, $3
}'
