#!/bin/zsh
# Test the AWS/kube extra row in zshprompt, and the Mac U.S. input
# source hook. The extra row must appear only when there is something
# to show. The input source tests run only against the osx prompt.
#
# Usage:
#   ~/bin/tests/zshprompt/test_zshprompt.sh
#   PROMPT_FILE=~/bin/settings/linux/home/zshprompt ~/bin/tests/zshprompt/test_zshprompt.sh

set -eu

PROMPT_FILE="${PROMPT_FILE:-$HOME/bin/settings/osx/home/zshprompt}"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: $PROMPT_FILE not found" >&2
  exit 2
fi

PASS=0
FAIL=0

C_GREEN=$'\e[32m'
C_RED=$'\e[31m'
C_OFF=$'\e[0m'

run_prompt() {
  local show_kube="$1"
  local show_aws="$2"
  local aws_profile="$3"
  local extra_path="${4:-}"

  local env_aws=()
  if [ -n "$aws_profile" ]; then
    env_aws=(AWS_PROFILE="$aws_profile")
  fi

  env -i \
    HOME="$HOME" \
    USER="${USER:-idachev}" \
    LOGNAME="${LOGNAME:-idachev}" \
    TERM="${TERM:-xterm-256color}" \
    PATH="${extra_path:+$extra_path:}$PATH" \
    OSTYPE="${OSTYPE:-}" \
    PWD="$PWD" \
    PR_SHOW_KUBE="$show_kube" \
    PR_SHOW_AWS="$show_aws" \
    "${env_aws[@]}" \
    zsh -f -c '
      source "'"$PROMPT_FILE"'"
      precmd
      print -r -- "PROMPT<<<${PROMPT}>>>"
      print -r -- "AWS<<<${PR_AWS_PROFILE-}>>>"
      print -r -- "KUBE<<<${PR_KUBE_NAMESPACE-}>>>"
      print -r -- "CLOUD<<<${PR_CLOUD_LINE-}>>>"
    '
}

field() {
  local blob="$1"
  local name="$2"
  local rest="${blob#*$name<<<}"
  print -r -- "${rest%%>>>*}"
}

segment_between_apm_and_path() {
  local prompt="$1"
  python3 -c '
import sys
p = sys.stdin.read()
a = "${(e)PR_APM}"
b = "$PR_BLUE"
i = p.find(a)
j = p.find(b)
if i < 0 or j < 0 or j < i:
    sys.exit(1)
sys.stdout.write(p[i + len(a):j])
' <<<"$prompt"
}

assert() {
  local name="$1"
  local ok="$2"
  local detail="${3:-}"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf '  %sPASS%s  %s\n' "$C_GREEN" "$C_OFF" "$name"
  else
    FAIL=$((FAIL + 1))
    printf '  %sFAIL%s  %s\n' "$C_RED" "$C_OFF" "$name"
    if [ -n "$detail" ]; then
      printf '        %s\n' "$detail"
    fi
  fi
}

echo
echo "=== $PROMPT_FILE ==="

out=$(run_prompt 0 0 "")
prompt="$(field "$out" PROMPT)"
ok=0
if [[ "$prompt" != *PR_AWS_PROFILE* && "$prompt" != *PR_KUBE_NAMESPACE* && "$prompt" != *PR_CLOUD_LINE* ]]; then
  # Flags off: the path row follows APM. No AWS/kube/cloud tokens.
  ok=1
fi
# Empty PR_CLOUD_LINE is also fine: the extra row is then a no-op.
if [[ "$prompt" == *'${(e)PR_CLOUD_LINE}'* && -z "$(field "$out" CLOUD)" ]]; then
  ok=1
fi
assert "flags off: no extra row between APM and path" \
  "$ok" \
  "prompt_tail=$(printf '%q' "$prompt")"

out=$(run_prompt 0 1 "")
seg=$(segment_between_apm_and_path "$(field "$out" PROMPT)")
cloud="$(field "$out" CLOUD)"
# Empty AWS/kube must not insert a row. Only the newline before path is ok.
has_hardcoded_empty_row=0
if [[ "$seg" == *$'\n${(e)PR_AWS_PROFILE}'* || "$seg" == *$'\n${(e)PR_KUBE_NAMESPACE}'* ]]; then
  has_hardcoded_empty_row=1
fi
ok=0
if [[ $has_hardcoded_empty_row -eq 0 && -z "$cloud" ]]; then
  ok=1
fi
assert "AWS flag on, empty AWS_PROFILE: no blank extra row" \
  "$ok" \
  "hardcoded_empty_row=$has_hardcoded_empty_row cloud=$(printf '%q' "$cloud") segment=$(printf '%q' "$seg")"

out=$(run_prompt 0 1 "work")
cloud="$(field "$out" CLOUD)"
aws="$(field "$out" AWS)"
ok=0
if [[ "$cloud" == $'\n'* && "$aws" == *'[aws '* && "$cloud" == *'${AWS_PROFILE}'* ]]; then
  ok=1
fi
assert "AWS flag on, AWS_PROFILE=work: extra row has aws" \
  "$ok" \
  "cloud=$(printf '%q' "$cloud") aws=$(printf '%q' "$aws")"

fake=$(mktemp -d)
trap 'command rm -rf -- "$fake"' EXIT
cat > "$fake/kubectl" <<'EOF'
#!/bin/sh
if [ "$1" = config ] && [ "$2" = view ]; then
  echo default
  exit 0
fi
if [ "$1" = config ] && [ "$2" = current-context ]; then
  echo minikube
  exit 0
fi
exit 1
EOF
chmod +x "$fake/kubectl"

out=$(run_prompt 1 0 "" "$fake")
cloud="$(field "$out" CLOUD)"
kube="$(field "$out" KUBE)"
ok=0
if [[ "$cloud" == $'\n'* && "$kube" == *'[kube '* && "$cloud" != $'\n' ]]; then
  ok=1
fi
assert "kube flag on, no AWS: extra row has kube" \
  "$ok" \
  "cloud=$(printf '%q' "$cloud") kube=$(printf '%q' "$kube")"

out=$(run_prompt 1 1 "work" "$fake")
cloud="$(field "$out" CLOUD)"
aws="$(field "$out" AWS)"
kube="$(field "$out" KUBE)"
ok=0
if [[ "$cloud" == $'\n'* && "$aws" == *'[aws '* && "$kube" == *'[kube '* ]]; then
  ok=1
fi
assert "AWS and kube both on: one extra row with both" \
  "$ok" \
  "cloud=$(printf '%q' "$cloud")"

run_precmd_input_source() {
  local interactive="$1"
  local workdir="$2"
  local stamp="$workdir/stamp"
  local bindir="$workdir/bin"

  command mkdir -p "$bindir"
  cat > "$bindir/macos_input_source" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$stamp"
EOF
  command chmod +x "$bindir/macos_input_source"
  : > "$stamp"

  local zsh_args=(-f)
  if [ "$interactive" = "1" ]; then
    zsh_args=(-f -i)
  fi

  env -i \
    HOME="$HOME" \
    USER="${USER:-idachev}" \
    LOGNAME="${LOGNAME:-idachev}" \
    TERM="${TERM:-xterm-256color}" \
    PATH="$bindir:$PATH" \
    PWD="$PWD" \
    zsh "${zsh_args[@]}" -c 'source "'"$PROMPT_FILE"'"; precmd'
}

case "$PROMPT_FILE" in
  *settings/osx/home/zshprompt)
    isrc_dir=$(mktemp -d)
    trap 'command rm -rf -- "$fake" "$isrc_dir"' EXIT

    run_precmd_input_source 0 "$isrc_dir/nonint"
    ok=0
    if [ ! -s "$isrc_dir/nonint/stamp" ]; then
      ok=1
    fi
    assert "non-interactive darwin precmd does not call macos_input_source" \
      "$ok" \
      "stamp=$(printf '%q' "$(command cat "$isrc_dir/nonint/stamp")")"

    run_precmd_input_source 1 "$isrc_dir/int"
    ok=0
    if [ "$(command cat "$isrc_dir/int/stamp")" = "us" ]; then
      ok=1
    fi
    assert "interactive darwin precmd calls macos_input_source us" \
      "$ok" \
      "stamp=$(printf '%q' "$(command cat "$isrc_dir/int/stamp")")"
    ;;
esac

echo
if [ "$FAIL" -gt 0 ]; then
  echo "FAILED: $FAIL  passed: $PASS"
  exit 1
fi
echo "OK: $PASS passed"
exit 0
