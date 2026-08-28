# gocryptfs private docs on macOS

Login Keychain unlocks `~/.storage_private_docs.crypt` at Aqua login.
FileVault login unlocks the Keychain, so Mac login = private docs.

Linux uses GPG files under `~/.gnupg/mount/` instead. See
`readmes/others/mount_yubikey_enc.md` and `~/bin/gocryptfs_storage_private_docs.sh`.

## Paths

| Role | Path |
| --- | --- |
| Cipherdir (local copy) | `~/.storage_private_docs.crypt` |
| Mount point | `~/storage_private_docs` |
| Plaintext docs | `~/personal/docs/private` → `~/storage_private_docs/docs` |
| Dropbox transport only | `~/Dropbox/sync/sync_storage_private_docs.crypt` |

Do not mount the Dropbox cipherdir. File Provider + FUSE is unstable.
Do not use Linux `gocryptfs_storage_private_docs.sh` / `crypt_unmount.sh` on macOS
(`fusermount`, LUKS `nvme`).

## One-time setup

Needs macFUSE and `~/go/bin/gocryptfs` (`brew_install_no_gui.sh`).

```bash
gocryptfs_storage_private_docs_osx.sh keychain-set
gocryptfs_storage_private_docs_osx.sh agent-install
gocryptfs_storage_private_docs_osx.sh status
```

`keychain-set` stores the gocryptfs password in the login Keychain
(service `gocryptfs-storage-private-docs`, account `$USER`, allow-all ACL so
launchd can read it).

`agent-install` writes
`~/Library/LaunchAgents/com.idachev.gocryptfs-storage-private-docs.plist`,
`launchctl bootstrap gui/$(id -u)` (no `sudo load`, no KeepAlive), then mounts
if needed.

Log: `~/Library/Logs/gocryptfs-storage-private-docs.log`.
Each run writes a start line and a stop line with a local timestamp.

## Commands

```bash
gocryptfs_storage_private_docs_osx.sh            # mount (default)
gocryptfs_storage_private_docs_osx.sh mount
gocryptfs_storage_private_docs_osx.sh unmount
gocryptfs_storage_private_docs_osx.sh status
gocryptfs_storage_private_docs_osx.sh keychain-set
gocryptfs_storage_private_docs_osx.sh agent-install
gocryptfs_storage_private_docs_osx.sh agent-uninstall
gocryptfs_storage_private_docs_osx_unmount.sh    # same as unmount
```

Unmount is Darwin `umount`, not `fusermount`.

## Keychain

Metadata only:

```bash
security find-generic-password -s gocryptfs-storage-private-docs -a "$USER"
```

Show the password (prints secret to the terminal):

```bash
security find-generic-password -s gocryptfs-storage-private-docs -a "$USER" -w
```

Or Keychain Access → login → `gocryptfs-storage-private-docs` → Show password.

## After reboot

`status` should show: mount `mounted`, keychain `present`, agent job `loaded`.
Plaintext path: `~/personal/docs/private`.

## Dropbox sync

Cipherdir and plaintext trees go to Dropbox via
`~/Dropbox/sync/sync_laptop_osx.sh`. The scheduler is a second LaunchAgent
(`sync_laptop_osx_agent.sh`), not this mount agent. See
`readmes/others/sync_laptop_osx.md`.
