# Dropbox laptop sync on macOS

`~/Dropbox/sync/sync_laptop_osx.sh` rsyncs local trees into Dropbox.
Linux uses `sync_laptop.sh` plus cron `5 */3 * * *`. On this Mac the
scheduler is a user LaunchAgent, not cron.

Empty or Finder-empty source dirs are skipped. `rsync --delete` must not
wipe the Dropbox dest when gocryptfs is unmounted or Finder left only
`.DS_Store`.

## Paths

| Role | Path |
| --- | --- |
| Sync script | `~/Dropbox/sync/sync_laptop_osx.sh` |
| Agent installer | `~/bin/sync_laptop_osx_agent.sh` |
| LaunchAgent | `~/Library/LaunchAgents/com.idachev.sync-laptop-osx.plist` |
| Log | `~/Library/Logs/sync-laptop-osx.log` |

Payload (with `doit`):

- `~/.storage_private_docs.crypt/` → `sync_storage_private_docs.crypt/`
- `~/bin/` → `sync_bin/`
- `~/personal/docs/public/` → `sync_docs_public/`
- `~/personal/docs/private/work/IGDBGSolutionsLtd/` → `sync_IGDBGSolutionsLtd/`

The last tree needs the gocryptfs volume. Mount agent:
`gocryptfs_storage_private_docs_osx.sh` / `readmes/others/gocryptfs_storage_private_docs_osx.md`.
Do not add `RunAtLoad` to this sync agent. It is a separate job.

## One-time setup

```bash
sync_laptop_osx_agent.sh install
sync_laptop_osx_agent.sh status
```

`install` writes the plist and `launchctl bootstrap gui/$(id -u)`
(no `sudo load`, no KeepAlive, no RunAtLoad). `PATH` starts with
`/opt/homebrew/bin` so launchd uses Homebrew `rsync`, not Apple `rsync`.

Grant Full Disk Access to `/bin/bash`. Dropbox lives under
`~/Library/CloudStorage/Dropbox` (File Provider). launchd runs `/bin/bash`
without Terminal/supacode TCC rights, so the job cannot read the sync
script or write the dest. Log line:

```
/bin/bash: .../CloudStorage/Dropbox/sync/sync_laptop_osx.sh: Operation not permitted
```

Exit code `126`. A terminal run of the same script can still work.

System Settings → Privacy & Security → Full Disk Access. Unlock the
list. Finder search does not show `/bin`. Use `+`, then Cmd+Shift+G,
path `/bin/bash`. Or `open -R /bin/bash` and drag `bash` onto the list.

Then:

```bash
launchctl kickstart -k "gui/$(id -u)/com.idachev.sync-laptop-osx"
command tail -n 40 ~/Library/Logs/sync-laptop-osx.log
```

Expect `Sync on ...` and rsync output, not `Operation not permitted`.

`status` exits 0 only when the job is loaded and the plist matches the
schedule. Preview without writing Dropbox:

```bash
~/Dropbox/sync/sync_laptop_osx.sh
```

Live run:

```bash
~/Dropbox/sync/sync_laptop_osx.sh doit
```

## Commands

```bash
sync_laptop_osx_agent.sh install
sync_laptop_osx_agent.sh uninstall
sync_laptop_osx_agent.sh status
sync_laptop_osx_agent.sh print-plist
```

## Schedule

Minute 5 every 3 hours: 00:05, 03:05, 06:05, 09:05, 12:05, 15:05, 18:05, 21:05.
Same as Linux cron `5 */3 * * *`.

If the Mac is asleep at that minute, launchd usually runs the missed job
after wake. cron would skip it.

## After install

`status` should show: plist `present`, job `loaded`, schedule `ok`,
`doit` yes, PATH `ok`, keepalive `absent`, runatload `absent`.
Log must not show `Operation not permitted`; that means `/bin/bash`
is missing Full Disk Access.

Tests: `~/bin/tests/dropbox_sync/test_dosync.sh` and
`~/bin/tests/dropbox_sync/test_agent.sh`.
