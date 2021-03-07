#!/bin/bash

if [ ! -d ~/storage_a/datastork ]; then
  echo -e "\nDO: gocryptfs_storage_a.sh"
fi

if [ ! -d ~/storage_private_docs/docs ]; then
  echo -e "\nDO: gocryptfs_storage_private_docs.sh"
fi

if [ ! -d ~/storage_ssd/lost+found ]; then
  echo -e "\nDO: sudo ~/bin/luks_mount.sh /dev/nvme1n1 $(realpath ~/storage_ssd)"
fi

if [ ! -d ~/storage_2tb/lost+found ]; then
  echo -e "\nDO: sudo ~/bin/luks_mount.sh /dev/sda $(realpath ~/storage_2tb)"
fi

