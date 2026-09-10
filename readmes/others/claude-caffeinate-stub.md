# claude-caffeinate-stub

Claude Code on macOS holds the machine awake for the whole session.
There is no official setting to turn that off. This stub is the local
workaround so the Mac can idle-sleep again (including with the lid
closed) while a `claude` session is open.

## Why

Claude Code `spawn()`s `caffeinate -i -t 300` via `PATH` during a
session and restarts it about every four minutes. That takes a
`PreventUserIdleSystemSleep` assertion. `killall caffeinate` does not
help: the parent process starts another one.

`~/.claude/settings.json` has no key for this. Upstream request:
[anthropics/claude-code#21432](https://github.com/anthropics/claude-code/issues/21432).
Idle-aware caffeinate ([#24889](https://github.com/anthropics/claude-code/issues/24889))
was closed as not planned.

Most community tools *add* keep-awake (lid-closed overnight agents).
This repo does the opposite: drop the built-in inhibitor.

## What we do

The macOS `claude` function in `settings/osx/home/aliases` prepends
`~/bin/claude-caffeinate-stub` to `PATH`, then runs the real binary
with `command claude`. Claude Code looks up `caffeinate` by name and
hits the no-op script (`exit 0`). `/usr/bin/caffeinate` stays the
system tool for everything else.

Do **not** put `claude-caffeinate-stub/` on the global `PATH`. That
would break real `caffeinate` uses (rsync, long copies).

## Files

| Path | Purpose |
|---|---|
| `~/bin/claude-caffeinate-stub/caffeinate` | No-op stand-in. Executable. Not on global `PATH`. |
| `settings/osx/home/aliases` (`claude` function) | Prepends the stub directory only for `claude`. |

Linux aliases are unchanged. Claude Code does not spawn macOS
`caffeinate` there.

## Use

Already-open shells need `source ~/.aliases`. A Claude process that
was started before the function existed still holds sleep — stop it
and start `claude` again.

`claudep` and `claude-mntr` go through the function. `claudehr`
(`headroom wrap claude`) passes `claude` as an argument, so the stub
does not apply there.

Check:

```
command -v caffeinate          # /usr/bin/caffeinate
type claude                    # shell function from ~/.aliases
pmset -g assertions            # no "caffeinate command-line tool" from claude
```
