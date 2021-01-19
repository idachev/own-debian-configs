> **WARNING:** After using it a while it has big problems on HDD and sometime
> on writes it gets too slow switching back to `encfs` :)

# GoCryptFS Releases

https://github.com/rfjakob/gocryptfs/releases

Unpack the new stable release here and execute: `install-gocryptfs.sh`

Default options to init: `gocryptfs -init -raw64 .dir.crypt`

## Useful

To check the plain file path in encrypted dir use:

`ls -li` to see the inode number, then `find . -inum`

(inode numbers are the same in encrypted and plain)

To unmount use: `fusermount -u mount-dir`

