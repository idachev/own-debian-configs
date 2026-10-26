# macOS settings

- `home/` — user dotfiles. Restore with `source create_links` (see repo root README).
- `system/` — copies under `etc/` for `/etc`. Restore with `sudo cp`, not
  symlinks. See `system/README.md`.

## LaunchAgents are not here

`~/Library/LaunchAgents/*.plist` is not backed up in this tree. `create_links`
does not touch it. The plist is generated on the machine.

On a new Mac, run the installer. Do not copy a plist from git into
`~/Library/LaunchAgents`.

| Job | Installer |
| --- | --- |
| `com.idachev.sync-laptop-osx` | `~/bin/sync_laptop_osx_agent.sh install` |
| `com.idachev.gocryptfs-storage-private-docs` | `~/bin/gocryptfs_storage_private_docs_osx.sh agent-install` |
| `com.idachev.nasa-photos` | `~/develop/personal/nasa-photos/agent_osx.sh install` |
| `com.idachev.worca-ui` | `~/bin/worca_ui_agent.sh install` |
| `com.mony.fixcyr` | `~/bin/fix-cyr/install.sh --capslock` |

More detail: `readmes/others/sync_laptop_osx.md`,
`readmes/others/gocryptfs_storage_private_docs_osx.md`,
`~/develop/personal/nasa-photos/README.md`.

`com.idachev.worca-ui` keeps the worca web UI on `http://localhost:4317`
from login and restarts it after a crash. `worca ui stop` stops it only for
about 10 seconds. Use `worca_ui_agent.sh uninstall` to stop it for good and
`worca_ui_agent.sh restart` instead of `worca ui restart`.

## Claude Code caffeinate stub

Claude Code keeps the Mac awake (`caffeinate -i -t 300`) and has no
off switch. The macOS `claude` function prepends a no-op `PATH` stub
so idle sleep works again. See `readmes/others/claude-caffeinate-stub.md`.

## Supacode

`home/create_links` links `~/.config/supacode` to
`~/bin/settings/osx/home/config/supacode`, like the other macOS configs.
The directory's `.gitignore` allows only `config.json` (application preferences
and shortcut overrides), `config.ghostty` (terminal settings and physical-key
bindings), and `.gitignore` itself.

`routes.json` contains machine-local repository paths; `repos.json` stores
repository-specific settings; `agents.json` reflects locally installed agent
integrations. These files, `.relocated`, corrupt backups, and new unknown files
stay local and are ignored. Existing local files must be backed up before
replacing a real `~/.config/supacode` directory with the symlink. The general
`link` helper asks to remove an existing directory; do not discard local state
when restoring on another Mac.

Supacode also reads the shared `~/.config/ghostty` config. Its own
`config.ghostty` loads afterward with the current `mergeAfterDefault` setting.
Application changes to tracked preferences appear as ordinary git changes.
Review script fields and paths in `config.json` before committing future edits.

### The Fork

The app is built from the fork `git@github-idachev:idachev/supacode.git`,
branch `idachev-supacode`, not from the Homebrew cask. The cask is the upstream
release: it does not have the fork's changes, and from 0.11.0 a release build
asks for a license after five local worktrees. Do not install the `supacode`
cask; `brew upgrade` would replace the fork with the upstream app. The fork's
own notes are in `docs/fork.md` in that repo.

First build on a Mac with Xcode:

1. Clone with submodules into `~/develop/github/supabitapp/supacode`:
   `git clone --recursive -b idachev-supacode git@github-idachev:idachev/supacode.git`.
   Add upstream for later merges:
   `git remote add upstream https://github.com/supabitapp/supacode.git`.
2. Finish the Xcode setup once:
   `sudo xcodebuild -license accept`, `sudo xcodebuild -runFirstLaunch`,
   `sudo xcodebuild -downloadComponent MetalToolchain`.
3. `mise install`, then `make doctor`. It prints the fix for each missing
   prerequisite.
4. Optional, but keeps macOS permissions across rebuilds: create a
   self-signed Code Signing certificate and a gitignored `Local.mk` with its
   SHA-1. See "Stable Code Signing For Dev Builds" in `docs/fork.md`.
5. `make install-dev-build`. It builds the Debug app (no license check) and
   copies it to `/Applications/supacode.app`. Restart Supacode.

Rebuild after new commits: `git pull`, `git submodule update --init --recursive`,
`make install-dev-build`, then restart Supacode. Terminal sessions run in zmx
and survive the restart. Log every build to a file under `tmp/claude-logs/`.

A Mac without Xcode (Command Line Tools are not enough) gets the app built on
another Mac. On the Mac with the build, after `make build-app`:

```bash
rsync -a --delete .build/DerivedData/Build/Products/Debug/supacode.app/ <host>:supacode-new/Supacode.app/
```

On the target: quit Supacode, move `/Applications/Supacode.app` to a backup,
move `~/supacode-new/Supacode.app` to `/Applications`, open it. A build signed
with the `Local.mk` certificate stays valid on the other Mac, and `rsync`
adds no quarantine flag.

## Karabiner And fix-cyr

Caps Lock switches between `ABC` and `Bulgarian - Phonetic` in a few
milliseconds. Karabiner-Elements maps Caps Lock to F18, and `fix-cyr` (a small
LaunchAgent in `~/bin/fix-cyr`) switches the input source on F18. The macOS
switch waits for the key release and is slow.

`home/create_links` links `~/.config/karabiner` to
`~/bin/settings/osx/home/config/karabiner`. Karabiner supports a symlinked
directory, not a symlinked `karabiner.json`. Only `karabiner.json` is in git;
`automatic_backups`, the `fix-cyr` backups and `assets` stay local.
`karabiner.json` holds `caps_lock -> f18`, the `` ` `` key as Hyper, and
`keyboard_type_v2 = iso`. Change the keyboard type on a Mac with an ANSI
keyboard.

On a new Mac:

1. Install Karabiner-Elements (`brew_install_all_goodies.sh` has it). It asks
   for the `sudo` password.
2. Run `source ~/bin/settings/osx/home/create_links` before Karabiner first
   starts, or back up and remove its own `~/.config/karabiner` first.
3. Open Karabiner-Elements and allow the driver extension and Input Monitoring.
4. Check that both layouts are enabled:
   `defaults read com.apple.HIToolbox AppleEnabledInputSources`. For `U.S.`
   instead of `ABC`, add `--layout-a com.apple.keylayout.US` to the install.
5. Run `~/bin/fix-cyr/install.sh --capslock`. It builds `fix-cyr/bin/fix-cyr`
   with `swiftc` (Command Line Tools are enough). It rewrites the
   `caps_lock -> f18` rule and leaves an ignored backup next to
   `karabiner.json`.
6. Privacy & Security -> Input Monitoring -> enable `~/bin/fix-cyr/bin/fix-cyr`.
7. Keyboard -> Input Sources -> turn off "Use Caps Lock to switch...".
8. Check `tail -n 5 /tmp/fix-cyr.log`: the `started` line shows
   `access=true`, and each key press adds a `toggle -> ...` line.

The `` ` `` key as Hyper does nothing by itself. Raycast holds the
Hyper+key hotkeys that open Supacode and the other apps. Raycast keeps its
settings in encrypted databases keyed to the Mac's keychain, so copying
`~/Library/Application Support/com.raycast.macos` does not work. Move them
with Raycast Settings -> Advanced -> Export, then Import on the new Mac.
Keep the `.rayconfig` file out of git: it can hold snippets, quicklinks and
extension preferences.

`~/bin/fix-cyr` is a copy of `~/develop/mentorano/fix-cyr`. Remove it with
`~/bin/fix-cyr/uninstall.sh`, not by hand. See `fix-cyr/README.md`.
