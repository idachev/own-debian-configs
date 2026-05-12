---
name: zoom-recorder-restore-vm
description: Bootstrap a freshly-launched zoom-recorder EC2 VM end-to-end from a local state tarball — rsync the repo, run setup-vm.sh, restore the tarball, hand off Tailscale auth interactively, push the rclone env, bounce VNC, and run the health check. Use when the user says "restore the VM", "restore zoom-recorder VM", "rebuild zoom recorder", "I created a new VM", "bootstrap the recorder", or any request that involves bringing up a new EC2 instance with the zoom-recorder backup. Make sure to use this skill whenever the user mentions restoring, rebuilding, or recreating the zoom-recorder VM, even if they do not explicitly say "restore" — and whenever they reference `~/bin/zoom-recorder/restore-fresh-vm.sh` or its surrounding workflow.
---

# zoom-recorder-restore-vm

Drives the zoom-recorder VM restore end-to-end without leaning on the interactive
`restore-fresh-vm.sh` (which blocks on TTY prompts and uses a broken
`import-environment` invocation). The skill orchestrates the lower-level scripts
directly so you can stream progress, retrieve the Tailscale auth URL up front,
and report the final VNC password.

## When to use

Trigger on any of:
- "restore the VM", "restore zoom-recorder VM", "rebuild zoom recorder"
- "I created a new VM", "I launched a new EC2 instance for zoom recorder"
- The user mentions `~/bin/zoom-recorder/restore-fresh-vm.sh`
- The user has just updated `~/.ssh/config` `HostName` for `zoom-recorder-aws`

Do **not** use for: routine recording sessions, health checks on an already-up
VM (use `health-check.sh` directly), or backup creation (`backup-vm-state.sh`).

## Prerequisites the user must have completed

1. New EC2 instance launched (Ubuntu 24.04/26.04 x86_64, t3.medium, 30 GB gp3).
2. `~/.ssh/config` `HostName` for `zoom-recorder-aws` updated to the new public
   IPv4 — `ssh zoom-recorder-aws true` must succeed.
3. At least one backup tarball exists under `~/bin/zoom-recorder/data/`.

If any of these is missing, surface it and stop — do not try to "fix it
forward" with destructive guesses.

## Project conventions (must follow)

These come from the user's global CLAUDE.md and are non-negotiable here:

- **Bypass shell aliases** with `command` for `tail`, `head`, `rm`, `cat`,
  `grep`, `ls`, `cp`, `mv`, `find`. So `command tail -n 20 file.log`, not
  `tail -n 20 file.log`.
- **POSIX form**: `tail -n 10`, not `tail -10`.
- **Long-running scripts must log to file** under `./tmp/claude-logs/` with a
  timestamp suffix (`$(date +%Y%m%d-%H%M%S)`). The setup step here is the long
  one; everything else is seconds.
- **Monitor scripts run under zsh** by default — wrap them in `bash -c '...'`
  if they use brace groups or other bash-isms, otherwise you will get
  `parse error near ...` and the monitor will fail-fast.

## Workflow

### Step 1 — sanity-check SSH

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 zoom-recorder-aws \
  'echo OK && uname -a && lsb_release -d 2>/dev/null'
```

If this fails, stop and tell the user to update `HostName` in `~/.ssh/config`.
Honor `ZOOM_VM_HOST` if they have set it.

### Step 2 — let the user pick the tarball

List all tarballs in `~/bin/zoom-recorder/data/`, newest first, with size and
mtime so the user can see what they are choosing between:

```bash
command ls -lh -t ~/bin/zoom-recorder/data/zoom-recorder-vm-state-*.tar.gz
```

Ask the user which one to restore (use `AskUserQuestion` if there are 2–4;
otherwise prompt as free text). Validate the chosen path is readable before
moving on. **Do not silently grab the newest** — the user explicitly asked
this skill to always confirm the tarball, because state files contain rclone
OAuth tokens and are easy to mix up across environments.

### Step 3 — rsync the repo to the VM

```bash
cd ~/bin/zoom-recorder && rsync -avz --delete \
  --exclude '.git' --exclude 'tmp' \
  ./ zoom-recorder-aws:~/zoom-recorder/
```

Tail the rsync output for sanity but expect it to be short.

### Step 4 — run setup-vm.sh on the VM (long step, ~2–3 min)

This is the only step worth backgrounding + monitoring. Log to file (per the
"long scripts log to file" rule), kick off in background, and watch with
Monitor.

```bash
mkdir -p ./tmp/claude-logs
LOG=./tmp/claude-logs/setup-vm-$(date +%Y%m%d-%H%M%S).log
echo "LOG=$LOG"
ssh zoom-recorder-aws 'cd ~/zoom-recorder && ./setup-vm.sh' > "$LOG" 2>&1 &
```

Use `Bash` with `run_in_background: true` so the task ID is captured and you
get a completion notification.

Then arm a Monitor that emits a tail summary every 5 s and exits when the
"Setup complete." marker appears or the log goes stable. Wrap the script in
`bash -c '...'` — the default shell is zsh and brace groups break it:

```bash
bash -c '
LOG=$(ls -t ~/bin/tmp/claude-logs/setup-vm-*.log 2>/dev/null | head -n 1)
if [ -z "$LOG" ]; then echo "no log found"; exit 1; fi
echo "watching $LOG"
prev_total=0
stable=0
while true; do
  total=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  last=$(tail -n 1 "$LOG" 2>/dev/null | head -c 140)
  echo "[L=$total] $last"
  if tail -n 50 "$LOG" 2>/dev/null | grep -qE "VNC password:|Tailscale IP:|Setup complete|^Done\."; then
    echo "=== completion marker found ==="
    tail -n 40 "$LOG"
    break
  fi
  if [ "$total" = "$prev_total" ]; then
    stable=$((stable+1))
    if [ "$stable" -ge 6 ]; then
      echo "=== log stable for 30s — finished or stuck ==="
      tail -n 30 "$LOG"
      break
    fi
  else
    stable=0
  fi
  prev_total=$total
  sleep 5
done
'
```

When the background `ssh` task notifies completion (exit 0), the monitor
will also exit on the marker. If exit ≠ 0, read the log and surface the
failing tail to the user — do not retry blindly.

### Step 5 — restore the state tarball

```bash
~/bin/zoom-recorder/restore-vm-state.sh /absolute/path/to/chosen-tarball.tar.gz
```

This is fast (seconds). It restores: rclone gdrive token, VNC password
(hashed + plaintext in `~/.config/tigervnc/.passwd-plain`),
`ZOOM_REC_REMOTE` env file, and the per-mp4 upload markers.

### Step 6 — Tailscale auth (interactive, but you drive the handoff)

A new EC2 instance is never authenticated, so do not bother with
`tailscale status` short-circuiting unless the user explicitly tells you
they have already done it. Kick off `sudo tailscale up --qr` in the
background on the VM, sleep briefly, then fetch the auth URL out of the log:

```bash
ssh zoom-recorder-aws '> /tmp/tailscale-up.log;
  sudo nohup tailscale up --qr </dev/null >/tmp/tailscale-up.log 2>&1 & disown'
sleep 5
ssh zoom-recorder-aws 'cat /tmp/tailscale-up.log'
```

Extract the `https://login.tailscale.com/a/...` URL and present it to the
user clearly. **Tell them you cannot complete the auth yourself** — they
have to open the URL in a browser where they are signed into Tailscale.

Wait for the user to say it is done. Then verify:

```bash
ssh zoom-recorder-aws 'sudo tailscale status | head -n 3; echo "---"; sudo tailscale ip -4'
```

Note the new VM's Tailscale IP — RealVNC bookmarks on the phone need updating.

### Step 7 — push env into the running systemd-user session, bounce VNC

⚠ The recommendation printed by `restore-vm-state.sh` uses
`systemctl --user import-environment ZOOM_REC_REMOTE < <(grep ...)`. This is
broken: `import-environment` reads from the calling shell's environment, not
stdin. The error `Environment variable $ZOOM_REC_REMOTE not set, ignoring.`
will look benign but the env will not be set in the systemd-user manager,
the uploader autostart will not see the remote on next launch, and the
follow-up `restart vncserver@:1` will silently start clean without the env.

Use `set-environment` instead, sourcing the value from the restored env
file so we do not hardcode it here:

```bash
ssh zoom-recorder-aws '
  set -e
  val=$(grep "^ZOOM_REC_REMOTE=" ~/.config/environment.d/zoom-recorder.conf | head -n 1)
  echo "from file: $val"
  systemctl --user set-environment "$val"
  systemctl --user restart vncserver@:1
  sleep 3
  systemctl --user is-active vncserver@:1
  systemctl --user show-environment | grep ZOOM_REC_REMOTE
'
```

You should see `active` and `ZOOM_REC_REMOTE=gdrive:ZoomRecordings`.

If the user's local `~/.ssh/config` has a `LocalForward 5901 localhost:5901`,
expect to see `bind [127.0.0.1]:5901: Address already in use` — that is just
their existing tunnel, not a real problem. Mention it briefly so the user
isn't alarmed.

### Step 8 — health check

```bash
~/bin/zoom-recorder/health-check.sh
```

What "healthy after restore" looks like (cross-check before reporting done):
- `vncserver : active (NRestarts=0)`
- `monitor` / `uploader` / `inotify` show real PIDs (not `NONE`)
- `env : ZOOM_REC_REMOTE=gdrive:ZoomRecordings`
- `rclone : gdrive:` configured
- `tailscale : <new IP>` populated
- `sinks : 1 zoom_sink module(s)` (no duplicates)
- `files : 0 mp4 / N marked uploaded` — backlog markers carried over so
  the uploader will not re-push old segments

If any of these is off, surface it. The most common miss is `ZOOM_REC_REMOTE`
not propagating (Step 7 was skipped or used `import-environment`).

### Step 9 — fetch the VNC password and report

The restored password lives at `~/.config/tigervnc/.passwd-plain` on the VM:

```bash
ssh zoom-recorder-aws 'cat ~/.config/tigervnc/.passwd-plain'
```

Print it to the user along with the Tailscale IP. The fresh-VM password
printed by `setup-vm.sh` (visible in the setup log) is the disposable one
that was overwritten by Step 5 — do not paste that one; users have lost
time confused by which password is current.

## Final report template

End with a compact table — pass rate of the checks, plus the two credentials
the user actually needs:

```
✅ Restore complete

| Check                  | Status                  |
| ---------------------- | ----------------------- |
| VNC server             | active                  |
| zoom_sink              | 1 module                |
| monitor / uploader     | running                 |
| ZOOM_REC_REMOTE        | gdrive:ZoomRecordings   |
| Tailscale IP           | 100.x.y.z               |

VNC password: <from .passwd-plain>

Notes:
- New Tailscale IP — update RealVNC bookmarks on the phone.
- The bind 5901 warning (if any) is your local SSH LocalForward, not a real issue.
```

## Gotchas worth re-reading next time

- The setup script prints a temporary fresh-VM VNC password mid-log. That is
  **not** the one to give the user — it is overwritten by Step 5.
- `restore-fresh-vm.sh` exists but blocks on a `read -r -p` for Tailscale and
  uses the broken `import-environment` pattern. Do **not** call it.
- Monitor commands run under zsh by default. Wrap in `bash -c '...'` if you
  use brace groups, `$((...))`, or other shell-sensitive constructs.
- The previous VM stays in `tailscale status` as "offline, last seen …" until
  the user removes it from the Tailscale admin console. Not a bug.
- `restore-vm-state.sh` saves pre-restore state on the VM under
  `~/.config/zoom-recorder-pre-restore-<timestamp>` — useful if you want to
  diff what changed.
