# GoCryptFS Releases

https://github.com/rfjakob/gocryptfs/releases

Unpack the new stable release here and execute: `install-gocryptfs.sh`

Default options to init: `gocryptfs -init -raw64 .dir.crypt`

## Useful

To check the plain file path in encrypted dir use:

`ls -li` to see the inode number, then `find . -inum`

(inode numbers are the same in encrypted and plain)

To unmount use: `fusermount -u mount-dir`

## Wrapper scripts (this repo)

Linux private docs: `~/bin/gocryptfs_storage_private_docs.sh` (GPG password
files). See `readmes/others/mount_yubikey_enc.md`. Interactive check:
`crypt_check.sh` from `settings/linux/home/zshrc`.

macOS private docs: `~/bin/gocryptfs_storage_private_docs_osx.sh` (login
Keychain + LaunchAgent). See `readmes/others/gocryptfs_storage_private_docs_osx.md`.
Unmount is `umount`, not `fusermount`.

