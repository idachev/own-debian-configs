#!/bin/bash
# CLI contract for macos_input_source.
# Compiles the C source to a temp binary.
# `us` selects U.S. on this Mac; that is the feature under test.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT}/macos_input_source.c"

PASS=0
FAIL=0

assert() {
  local name="$1"
  local ok="$2"
  local detail="${3:-}"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    echo "PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $name"
    if [ -n "$detail" ]; then
      printf '      %s\n' "$detail"
    fi
  fi
}

echo "=== macos_input_source ==="

if [ "$(uname -s)" != Darwin ]; then
  echo "SKIP  not Darwin"
  exit 0
fi

if [ ! -f "$SRC" ]; then
  echo "FAIL  source missing: $SRC"
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'command rm -rf -- "$WORKDIR"' EXIT
BIN="${WORKDIR}/macos_input_source"

if ! clang -Os -framework Carbon -o "$BIN" "$SRC"; then
  echo "FAIL  clang macos_input_source.c"
  exit 1
fi

out="$("$BIN" 2>"${WORKDIR}/err")" || rc=$?
rc="${rc:-0}"
ok=0
if [ "$rc" -eq 0 ] && [[ "$out" == com.apple.keylayout.* ]]; then
  ok=1
fi
assert "no args prints current keylayout id" \
  "$ok" \
  "rc=$rc out=$(printf '%q' "$out") err=$(printf '%q' "$(command cat "${WORKDIR}/err")")"

"$BIN" bogus >"${WORKDIR}/out" 2>"${WORKDIR}/err" || rc=$?
rc="${rc:-0}"
ok=0
if [ "$rc" -eq 2 ] && command grep -q 'usage:' "${WORKDIR}/err"; then
  ok=1
fi
assert "bogus arg exits 2 with usage" \
  "$ok" \
  "rc=$rc out=$(printf '%q' "$(command cat "${WORKDIR}/out")") err=$(printf '%q' "$(command cat "${WORKDIR}/err")")"

rc=0
"$BIN" us >"${WORKDIR}/out" 2>"${WORKDIR}/err" || rc=$?
AFTER="$("$BIN")"
ok=0
if [ "$rc" -eq 0 ] && [ "$AFTER" = "com.apple.keylayout.US" ] &&
  [ ! -s "${WORKDIR}/out" ]; then
  ok=1
fi
assert "us selects com.apple.keylayout.US and prints nothing" \
  "$ok" \
  "rc=$rc after=$(printf '%q' "$AFTER") out=$(printf '%q' "$(command cat "${WORKDIR}/out")") err=$(printf '%q' "$(command cat "${WORKDIR}/err")")"

rc=0
"$BIN" us >"${WORKDIR}/out" 2>"${WORKDIR}/err" || rc=$?
ok=0
if [ "$rc" -eq 0 ] && [ "$("$BIN")" = "com.apple.keylayout.US" ]; then
  ok=1
fi
assert "us is a no-op when already U.S." \
  "$ok" \
  "rc=$rc current=$(printf '%q' "$("$BIN")")"

echo
if [ "$FAIL" -gt 0 ]; then
  echo "FAILED: $FAIL  passed: $PASS"
  exit 1
fi
echo "OK: $PASS passed"
exit 0
