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
