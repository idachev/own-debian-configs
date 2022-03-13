#!/bin/bash

OK=1

if [ ! -d ~/storage_a/datastork ]; then
  echo -e "\nDO: gocryptfs_storage_a.sh"
  OK=0
fi

if [ ! -d ~/storage_private_docs/docs ]; then
  echo -e "\nDO: gocryptfs_storage_private_docs.sh"
  OK=0
fi

if [ ! -d ~/storage_b/lost+found ]; then
  echo -e "\nDO: sudo ~/bin/luks_mount.sh /dev/nvme1n1 $(realpath ~/storage_b) "'${USER}'
  OK=0
fi

if [ ! -d ~/storage_c/lost+found ]; then
  echo -e "\nDO: sudo ~/bin/luks_mount.sh /dev/nvme2n1 $(realpath ~/storage_c) "'${USER}'
  OK=0
fi

if [ "${OK}" = "1" ]; then
  echo -e "\nALL CRYPT MOUNTS ARE OK\n"
fi

