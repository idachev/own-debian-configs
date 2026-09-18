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
  sync)
    logf=""; dry=0
    prev=""
    for a in "$@"; do
      [[ "${prev}" == "--log-file" ]] && logf="$a"
      [[ "$a" == "--dry-run" || "$a" == "-n" ]] && dry=1
      prev="$a"
    done
    if [[ ${dry} -eq 1 && -n "${logf}" && -n "${RCLONE_FAKE_DELETES:-}" ]]; then
      for d in ${RCLONE_FAKE_DELETES}; do
        echo "2026/09/18 00:00:00 NOTICE: ${d}: Skipped delete as --dry-run is set (size 10)" >> "${logf}"
      done
      echo "2026/09/18 00:00:00 NOTICE: Google drive root 'mirror': Skipped delete as --dry-run is set" >> "${logf}"
    fi
    exit "${RCLONE_EXIT:-0}" ;;
  copy|copyto) exit "${RCLONE_EXIT:-0}" ;;
  lsjson)
    [[ -n "${RCLONE_LSJSON_EXIT:-}" ]] && exit "${RCLONE_LSJSON_EXIT}"
    for a in "$@"; do case "$a" in *:*) target="$(remote_of "$a")";; esac; done
    if [[ -d "${target}" ]]; then printf '{\n\t"Path": "",\n\t"Size": -1,\n\t"IsDir": true\n}\n'; exit 0; fi
    if [[ -f "${target}" ]]; then printf '{\n\t"Path": "x",\n\t"Size": %s,\n\t"IsDir": false\n}\n' "$(wc -c < "${target}" | tr -d ' ')"; exit 0; fi
    exit 3 ;;
  lsf)
    target=""
    for a in "$@"; do case "$a" in *:*) target="$(remote_of "$a")";; esac; done
    if [[ -z "${target}" ]]; then
      # local listing: the first non-flag argument after lsf
      shift; for a in "$@"; do case "$a" in -*) ;; *) target="$a"; break;; esac; done
      [[ -n "${RCLONE_LSF_LOCAL_EXIT:-}" ]] && exit "${RCLONE_LSF_LOCAL_EXIT}"
      (cd "${target}" && find . -type f -name '*.mp4' | sed 's|^\./||' | sort); exit 0
    fi
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
check "push: uses the exclude file" "grep -q -- '--exclude-from ${REPO}/.gdrive-repo-exclude.txt' '${RCLONE_LOG}'"
check "push: passes extra flags through" "grep -q -- '--transfers 3' '${RCLONE_LOG}'"
check "push: works from a subdirectory (log under repo tmp/)" "[[ \"\${out}\" == *\"log:  ${REPO}/tmp/claude-logs/gdrive-push-\"* ]]" "${out}"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && GDRIVE_MAX_DELETE=5 "${BIN}/gdrive-repo-push.sh" 2>&1)"
check "push: GDRIVE_MAX_DELETE switches to sync --max-delete 5" "grep -q '^sync .* --max-delete 5$' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && RCLONE_EXIT=7 "${BIN}/gdrive-repo-push.sh" 2>&1)"; rc=$?
check "push: propagates rclone's exit code" "[[ ${rc} -eq 7 ]]"

out="$(cd "${WORK}" && "${BIN}/gdrive-repo-push.sh" 2>&1)"; rc=$?
check "push: exit 2 without a conf" "[[ ${rc} -eq 2 ]] && [[ "\${out}" == *'no .gdrive-repo.conf'* ]]" "${out}"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-push.sh" 2>&1)"
check "push: no git bundle without GDRIVE_GIT_BUNDLE" "! grep -q '^copyto .*\.bundle' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"

echo 'GDRIVE_GIT_BUNDLE=1' >> "${REPO}/.gdrive-repo.conf"
: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-push.sh" --dry-run 2>&1)"; rc=$?
check "push: GDRIVE_GIT_BUNDLE=1 uploads <repo>.bundle to .git-backup/ by checksum" \
  "grep -q '^copyto .*/repo\.bundle fake:mirror/\.git-backup/repo\.bundle --checksum .* --dry-run$' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
check "push: bundle upload happens before the tree copy" "[[ \"\$(head -n 1 '${RCLONE_LOG}')\" == copyto* ]]" "$(command cat "${RCLONE_LOG}")"
check "push: bundle run exits 0" "[[ ${rc} -eq 0 ]]" "${out}"
check "push: bundle is packed single-threaded (deterministic)" "grep -q 'pack.threads=1' '${BIN}/gdrive-repo-push.sh'"
check "push: tree copy excludes .git-backup/** so sync mode cannot delete the bundle" "grep -q '^copy \. fake:mirror/ .*--exclude \.git-backup/\*\*' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-push.sh" -n 2>&1)"
check "push: rclone's short -n reaches the bundle upload too" "grep -q '^copyto .*repo\.bundle .* -n$' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
bundle_ok="$(cd "${REPO}" && b="$(command mktemp)" && git bundle create "$b" --all >/dev/null 2>&1 && git bundle verify "$b" >/dev/null 2>&1 && echo yes; command rm -f "$b")"
check "git bundle --all of the test repo verifies" "[[ '${bundle_ok}' == yes ]]"
command sed -i.bak '/GDRIVE_GIT_BUNDLE/d' "${REPO}/.gdrive-repo.conf" && command rm -f "${REPO}/.gdrive-repo.conf.bak"

# ---- push: GDRIVE_SYNC_NON_MEDIA ----------------------------------------------
echo 'GDRIVE_SYNC_NON_MEDIA=1' >> "${REPO}/.gdrive-repo.conf"
: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-push.sh" </dev/null 2>&1)"; rc=$?
check "sync mode: no deletions -> preview, real sync with --max-delete 0, then media copy" \
  "[[ ${rc} -eq 0 ]] && [[ \"\$(grep -c '^sync ' '${RCLONE_LOG}')\" == 2 ]] && grep -q '^sync .*--filter-from .*/non-media.filter .*--max-delete 0$' '${RCLONE_LOG}' && grep -q '^copy \. fake:mirror/ --filter-from .*/media.filter' '${RCLONE_LOG}'" "${out}
$(command cat "${RCLONE_LOG}")"
check "sync mode: preview is a dry run" "grep -q '^sync .*--dry-run$' '${RCLONE_LOG}'"
check "sync mode: says no deletions pending" "[[ \"\${out}\" == *'no Drive-side deletions pending'* ]]" "${out}"
rules="$(cd "${REPO}" && bash -c 'source "$0"; gdrive_load_conf; gdrive_non_media_filter_flags; cat "${GDRIVE_NON_MEDIA_FILTER_FLAGS[1]}"' "${BIN}/gdrive-repo-lib.sh")"
check "non-media filter: excludes, .git-backup, media extensions, then '+ **'" "[[ \"\${rules}\" == \$'- tmp/**\\n- .git-backup/**\\n- *.mp4\\n- *.m4a\\n+ **' ]]" "${rules}"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && RCLONE_FAKE_DELETES="docs/old.md scripts/gone.sh" "${BIN}/gdrive-repo-push.sh" </dev/null 2>&1)"; rc=$?
check "sync mode: pending deletions without a tty and without --yes -> exit 1" "[[ ${rc} -eq 1 ]]" "${out}"
check "sync mode: the deletion list is printed" "[[ \"\${out}\" == *'  - docs/old.md'* && \"\${out}\" == *'  - scripts/gone.sh'* && \"\${out}\" == *'2 non-media file(s)'* ]]" "${out}"
check "sync mode: nothing real ran after the refused preview" "[[ \"\$(grep -c '^sync ' '${RCLONE_LOG}')\" == 1 ]] && ! grep -q '^copy ' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
check "sync mode: the Drive root NOTICE line is not counted as a deletion" "[[ \"\${out}\" != *'Google drive root'* ]]" "${out}"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && RCLONE_FAKE_DELETES="docs/old.md scripts/gone.sh" "${BIN}/gdrive-repo-push.sh" --yes </dev/null 2>&1)"; rc=$?
check "sync mode: --yes runs the real sync capped at the previewed count" "[[ ${rc} -eq 0 ]] && grep -q '^sync .*--max-delete 2$' '${RCLONE_LOG}' && grep -q '^copy ' '${RCLONE_LOG}'" "${out}
$(command cat "${RCLONE_LOG}")"
check "sync mode: --yes is not passed through to rclone" "! grep -q -- '--yes' '${RCLONE_LOG}'"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && RCLONE_FAKE_DELETES="docs/old.md" "${BIN}/gdrive-repo-push.sh" --dry-run </dev/null 2>&1)"; rc=$?
check "sync mode: user --dry-run lists deletions, asks nothing, runs no real sync, exit 0" \
  "[[ ${rc} -eq 0 ]] && [[ \"\${out}\" == *'  - docs/old.md'* ]] && [[ \"\$(grep -c '^sync ' '${RCLONE_LOG}')\" == 1 ]] && grep -q '^copy .*--dry-run$' '${RCLONE_LOG}'" "${out}
$(command cat "${RCLONE_LOG}")"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && printf 'y\n' | RCLONE_FAKE_DELETES="docs/old.md" "${BIN}/gdrive-repo-push.sh" 2>&1)"; rc=$?
# stdin is a pipe, not a tty, so the prompt path is not reachable in tests; assert the non-tty refusal instead
check "sync mode: piped stdin is not a tty -> still refuses without --yes" "[[ ${rc} -eq 1 && \"\${out}\" == *'no terminal to confirm'* ]]" "${out}"
command sed -i.bak '/GDRIVE_SYNC_NON_MEDIA/d' "${REPO}/.gdrive-repo.conf" && command rm -f "${REPO}/.gdrive-repo.conf.bak"

# ---- pull -----------------------------------------------------------------
printf 'AAAA' > "${FAKE_REMOTE}/media/a/one.mp4"
printf 'BB'   > "${FAKE_REMOTE}/media/a/two.mp4"
: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" media/a 2>&1)"; rc=$?
check "pull dir: exit 0" "[[ ${rc} -eq 0 ]]" "${out}"
check "pull dir: rclone copy with the media filter file" "grep -q '^copy fake:mirror/media/a media/a --filter-from .*/media.filter' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
filter_file="$(command sed -n 's/^copy .* --filter-from \([^ ]*\).*/\1/p' "${RCLONE_LOG}" | command head -n 1)"
# The filter file is deleted on exit; regenerate it via a sourced lib call to inspect the rules.
rules="$(cd "${REPO}" && bash -c 'source "$0"; gdrive_load_conf; gdrive_media_filter_flags; cat "${GDRIVE_MEDIA_FILTER_FLAGS[1]}"' "${BIN}/gdrive-repo-lib.sh")"
check "filter file: excludes first, then media includes, then '- *'" "[[ \"\${rules}\" == \$'- tmp/**\\n+ *.mp4\\n+ *.m4a\\n- *' ]]" "${rules}"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" ./media/a/one.mp4 2>&1)"; rc=$?
check "pull file: copyto by path" "grep -q '^copyto fake:mirror/media/a/one.mp4 media/a/one.mp4' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"

: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" media/nope 2>&1)"; rc=$?
check "pull: absent path fails with 'not on Drive', no copy attempted" "[[ ${rc} -eq 1 && \"\${out}\" == *'not on Drive'* ]] && ! grep -q '^copy' '${RCLONE_LOG}'" "${out}"
: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && RCLONE_LSJSON_EXIT=5 "${BIN}/gdrive-repo-pull.sh" media/a 2>&1)"; rc=$?
check "pull: failed Drive stat fails the path instead of an unfiltered copyto" "[[ ${rc} -eq 1 && \"\${out}\" == *'Drive check failed'* ]] && ! grep -q '^copy' '${RCLONE_LOG}'" "${out}
$(command cat "${RCLONE_LOG}")"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" --list media/a media/b 2>&1)"; rc=$?
check "list: more than one path is refused with exit 2" "[[ ${rc} -eq 2 && \"\${out}\" == *'at most one directory'* ]]" "${out}"
out="$(cd "${REPO}" && RCLONE_LSF_LOCAL_EXIT=6 "${BIN}/gdrive-repo-pull.sh" --list media 2>&1)"; rc=$?
check "list: failed local listing is exit 2, not '0 local-only'" "[[ ${rc} -eq 2 && \"\${out}\" == *'local listing'* ]]" "${out}"
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
check "list: local listing uses the same media filter file" "grep -q -- '^lsf -R --files-only media --filter-from .*/media.filter' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" --list 2>&1)"; rc=$?
check "list: whole repo without a path" "[[ ${rc} -eq 0 ]] && [[ "\${out}" == *'present     media/a/one.mp4'* ]]" "${out}"
check "list: whole repo classifies local files (no ./ prefix leak)" "[[ "\${out}" == *'summary: 1 present, 1 differs, 1 drive-only, 1 local-only'* ]]" "${out}"
printf 'ZZ' > "${REPO}/media/b/xone.mp4"   # suffix of one.mp4 — must not read as present
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" --list media 2>&1)"
check "list: suffix name is local-only, not matched to another file" "[[ "\${out}" == *'local-only  media/b/xone.mp4'* ]]" "${out}"
command rm -f "${REPO}/media/b/xone.mp4"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-pull.sh" --list media/nope 2>&1)"; rc=$?
check "list: unknown directory is exit 2 with a clear message" "[[ ${rc} -eq 2 && "\${out}" == *'no such directory on Drive'* ]]" "${out}"

# ---- prune ----------------------------------------------------------------
printf 'TRACKED' > "${REPO}/media/a/tracked.mp4"
(cd "${REPO}" && git add -f media/a/tracked.mp4 && git -c user.email=t@t -c user.name=t commit -qm track)
command cp "${REPO}/media/a/tracked.mp4" "${FAKE_REMOTE}/media/a/tracked.mp4"
: > "${RCLONE_LOG}"
out="$(cd "${REPO}" && "${BIN}/gdrive-repo-prune.sh" --dry-run media 2>&1)"; rc=$?
check "prune dry-run: exit 1 because of refusals" "[[ ${rc} -eq 1 ]]" "${out}"
check "prune: local walk goes through the media filter (push excludes apply)" "grep -q '^lsf -R --files-only media --filter-from .*/media.filter' '${RCLONE_LOG}'" "$(command cat "${RCLONE_LOG}")"
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
