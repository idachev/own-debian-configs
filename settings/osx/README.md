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

More detail: `readmes/others/sync_laptop_osx.md`,
`readmes/others/gocryptfs_storage_private_docs_osx.md`,
`~/develop/personal/nasa-photos/README.md`.

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
