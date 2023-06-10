#!/bin/bash

OK=1
GPG_CHECK=1

function show_gpg_check() {
  if [ "${GPG_CHECK}" = "1" ]; then
    echo -e "To unlock gpg card pin execute: gpg_mount_pin_unlock.sh"
    echo -e "You may need to do: sudo systemctl stop pcscd"
    echo -e "Restart it again after mounting: sudo systemctl start pcscd\n"
    GPG_CHECK=0
  fi
}

if [ ! -d ~/storage_a/datastork ]; then
  show_gpg_check
  echo -e "DO: gocryptfs_storage_a.sh && crypt_check.sh\n"
  OK=0
fi

if [ ! -d ~/storage_private_docs/docs ]; then
  show_gpg_check
  echo -e "DO: gocryptfs_storage_private_docs.sh && crypt_check.sh\n"
  OK=0
fi

if [ ! -d ~/storage_b/lost+found ]; then
  show_gpg_check
  echo -e "DO: sudo ~/bin/luks_mount.sh /dev/nvme1n1 $(realpath ~/storage_b) "'${USER}'" && crypt_check.sh\n"
  OK=0
fi

if [ ! -d ~/storage_c/lost+found ]; then
  show_gpg_check
  echo -e "DO: sudo ~/bin/luks_mount.sh /dev/nvme0n1 $(realpath ~/storage_c) "'${USER}'" && crypt_check.sh\n"
  OK=0
fi

if [ "${OK}" = "1" ]; then
  echo -e "\nALL CRYPT MOUNTS ARE OK\n"
else
  echo -e "\nDo all at once:\
   gocryptfs_storage_a.sh && \
   gocryptfs_storage_private_docs.sh && \
   sudo ~/bin/luks_mount.sh /dev/nvme1n1 $(realpath ~/storage_b) "'${USER}'" && \
   sudo ~/bin/luks_mount.sh /dev/nvme0n1 $(realpath ~/storage_c) "'${USER}'
fi

