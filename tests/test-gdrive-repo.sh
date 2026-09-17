#!/bin/bash
# Tests for gdrive-repo-{push,pull,prune}.sh with a fake rclone on PATH.
# Run: ~/bin/tests/test-gdrive-repo.sh
set -uo pipefail

BIN="$(cd "$(command dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(command mktemp -d)"
trap 'command rm -rf "${WORK}"' EXIT

FAKE="${WORK}/fakebin"
command mkdir -p "${FAKE}"
# The fake rclone appends its argv to a log and answers from a scripted
# "remote": a directory tree under $FAKE_REMOTE whose files' sizes are
# returned by `lsjson --stat` and listed by `lsf`.
command cat > "${FAKE}/rclone" <<'FAKE'
#!/bin/bash
echo "$*" >> "${RCLONE_LOG}"
cmd="$1"
remote_of() { local a="$1"; a="${a#*:}"; a="${a#mirror}"; a="${a#/}"; echo "${FAKE_REMOTE}/${a}"; }
case "${cmd}" in
  copy|sync|copyto) exit "${RCLONE_EXIT:-0}" ;;
  lsjson)
    for a in "$@"; do case "$a" in *:*) target="$(remote_of "$a")";; esac; done
    if [[ -d "${target}" ]]; then echo '{"Path":"x","IsDir":true}'; exit 0; fi
    if [[ -f "${target}" ]]; then printf '{"Path":"x","Size":%s,"IsDir":false}\n' "$(wc -c < "${target}" | tr -d ' ')"; exit 0; fi
    exit 3 ;;
  lsf)
    for a in "$@"; do case "$a" in *:*) target="$(remote_of "$a")";; esac; done
    target="${target%/}"
    [[ -d "${target}" ]] || exit 3
    (cd "${target}" && find . -type f -name '*.mp4' | sed 's|^\./||' | while read -r f; do printf '%s|%s\n' "$f" "$(wc -c < "$f" | tr -d ' ')"; done) ;;
  *) exit 0 ;;
esac
FAKE
command chmod +x "${FAKE}/rclone"
export PATH="${FAKE}:${PATH}"
export RCLONE_LOG="${WORK}/rclone.log"
export FAKE_REMOTE="${WORK}/remote/mirror"

REPO="${WORK}/repo"
command mkdir -p "${REPO}/media/a" "${REPO}/media/b" "${FAKE_REMOTE}/media/a" "${FAKE_REMOTE}/media/b"
command cat > "${REPO}/.gdrive-repo.conf" <<CONF
GDRIVE_REMOTE=fake
GDRIVE_ROOT=mirror
GDRIVE_EXCLUDE_FILE=.gdrive-repo-exclude.txt
GDRIVE_MEDIA_EXTENSIONS="mp4 m4a"
CONF
echo 'tmp/**' > "${REPO}/.gdrive-repo-exclude.txt"
(cd "${REPO}" && git init -q && git add . && git -c user.email=t@t -c user.name=t commit -qm init)

pass=0 fail=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
nok()  { fail=$((fail + 1)); echo "FAIL - $1"; [[ -n "${2:-}" ]] && echo "       $2"; }
check() { if eval "$2"; then ok "$1"; else nok "$1" "${3:-}"; fi; }

# ---- push -----------------------------------------------------------------
: > "${RCLONE_LOG}"
out="$(cd "${REPO}/media" && "${BIN}/gdrive-repo-push.sh" --transfers 3 2>&1)"; rc=$?
check "push: exit 0 in copy mode" "[[ ${rc} -eq 0 ]]" "${out}"
check "push: runs rclone copy to fake:mirror/" "grep -q '^copy \. fake:mirror/ ' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
check "push: uses the exclude file" "grep -q -- '--exclude-from .gdrive-repo-exclude.txt' '${RCLONE_LOG}'"
check "push: passes extra flags through" "grep -q -- '--transfers 3' '${RCLONE_LOG}'"
check "push: works from a subdirectory (log under repo tmp/)" "[[ \"\${out}\" == *\"log: ${REPO}/tmp/claude-logs/gdrive-push-\"* ]]" "${out}"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && GDRIVE_MAX_DELETE=5 "${BIN}/gdrive-repo-push.sh" 2>&1)"
check "push: GDRIVE_MAX_DELETE switches to sync --max-delete 5" "grep -q '^sync .* --max-delete 5$' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && RCLONE_EXIT=7 "${BIN}/gdrive-repo-push.sh" 2>&1)"; rc=$?
check "push: propagates rclone's exit code" "[[ ${rc} -eq 7 ]]"

out="$(cd "${WORK}" && "${BIN}/gdrive-repo-push.sh" 2>&1)"; rc=$?
check "push: exit 2 without a conf" "[[ ${rc} -eq 2 ]] && [[ "\${out}" == *'no .gdrive-repo.conf'* ]]" "${out}"

# ---- pull -----------------------------------------------------------------
printf 'AAAA' > "${FAKE_REMOTE}/media/a/one.mp4"
printf 'BB'   > "${FAKE_REMOTE}/media/a/two.mp4"
: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" media/a 2>&1)"; rc=$?
check "pull dir: exit 0" "[[ ${rc} -eq 0 ]]" "${out}"
check "pull dir: rclone copy with media includes" "grep -q '^copy fake:mirror/media/a media/a --include \*.mp4 --include \*.m4a' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" ./media/a/one.mp4 2>&1)"; rc=$?
check "pull file: copyto by path" "grep -q '^copyto fake:mirror/media/a/one.mp4 media/a/one.mp4' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"

out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" media/nope.mp4 2>&1)"; rc=$?
# fake copyto exits 0, so this passes; the absent case is covered by lsjson exit 3 in prune
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" ../escape 2>&1)"; rc=$?
check "pull: refuses .. paths with exit 2" "[[ ${rc} -eq 2 ]]" "${out}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" /abs/path 2>&1)"; rc=$?
check "pull: refuses absolute paths with exit 2" "[[ ${rc} -eq 2 ]]" "${out}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" 2>&1)"; rc=$?
check "pull: no args prints usage, exit 2" "[[ ${rc} -eq 2 ]] && [[ "\${out}" == *Usage* ]]" "${out}"

# ---- pull --list ----------------------------------------------------------
printf 'AAAA' > "${REPO}/media/a/one.mp4"     # present, same size
printf 'B'    > "${REPO}/media/a/two.mp4"     # differs
printf 'CCC'  > "${REPO}/media/b/local.mp4"   # local-only
printf 'DDDD' > "${FAKE_REMOTE}/media/b/remote.mp4"  # drive-only
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" --list media 2>&1)"; rc=$?
check "list: exit 0" "[[ ${rc} -eq 0 ]]" "${out}"
check "list: present"    "[[ "\${out}" == *'present     media/a/one.mp4'* ]]" "${out}"
check "list: differs"    "[[ "\${out}" == *'differs     media/a/two.mp4'* ]]" "${out}"
check "list: drive-only" "[[ "\${out}" == *'drive-only  media/b/remote.mp4'* ]]" "${out}"
check "list: local-only" "[[ "\${out}" == *'local-only  media/b/local.mp4'* ]]" "${out}"
check "list: summary"    "[[ "\${out}" == *'summary: 1 present, 1 differs, 1 drive-only, 1 local-only'* ]]" "${out}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" --list 2>&1)"; rc=$?
check "list: whole repo without a path" "[[ ${rc} -eq 0 ]] && [[ "\${out}" == *'present     media/a/one.mp4'* ]]" "${out}"

# ---- prune ----------------------------------------------------------------
printf 'TRACKED' > "${REPO}/media/a/tracked.mp4"
(cd "${REPO}" && git add -f media/a/tracked.mp4 && git -c user.email=t@t -c user.name=t commit -qm track)
command cp "${REPO}/media/a/tracked.mp4" "${FAKE_REMOTE}/media/a/tracked.mp4"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-prune.sh" --dry-run media 2>&1)"; rc=$?
check "prune dry-run: exit 1 because of refusals" "[[ ${rc} -eq 1 ]]" "${out}"
check "prune dry-run: would-prune verified file" "[[ "\${out}" == *'would-prune media/a/one.mp4'* ]]" "${out}"
check "prune: refuses size mismatch"  "[[ "\${out}" == *'refused     media/a/two.mp4 — Drive has 2 bytes, local 1'* ]]" "${out}"
check "prune: refuses local-only"     "[[ "\${out}" == *'refused     media/b/local.mp4 — not on Drive'* ]]" "${out}"
check "prune: refuses git-tracked"    "[[ "\${out}" == *'refused     media/a/tracked.mp4 — tracked by git'* ]]" "${out}"
check "prune dry-run: nothing deleted" "[[ -f '${REPO}/media/a/one.mp4' && -f '${REPO}/media/a/two.mp4' ]]"

out="$(cd "${REPO}" && "${BIN}/gdrive-repo-prune.sh" media/a/one.mp4 2>&1)"; rc=$?
check "prune file: exit 0 and deleted" "[[ ${rc} -eq 0 && ! -f '${REPO}/media/a/one.mp4' ]]" "${out}"
check "prune file: reports pruned" "[[ "\${out}" == *'pruned      media/a/one.mp4 (4 bytes'* ]]" "${out}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-prune.sh" media/a/one.mp4 2>&1)"; rc=$?
check "prune: already-absent path is not an error" "[[ ${rc} -eq 0 && "\${out}" == *absent* ]]" "${out}"

# Drive call failure (not exit 3) must refuse, never delete.
printf 'EEEE' > "${REPO}/media/b/quota.mp4"
command cat > "${FAKE}/rclone" <<'FAKE'
#!/bin/bash
[[ "$1" == lsjson ]] && exit 1
exit 0
FAKE
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-prune.sh" media/b/quota.mp4 2>&1)"; rc=$?
check "prune: failed Drive check refuses and keeps the file" "[[ ${rc} -eq 1 && -f '${REPO}/media/b/quota.mp4' && "\${out}" == *'Drive check failed'* ]]" "${out}"

echo
echo "${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
