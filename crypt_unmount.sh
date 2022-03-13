#!/bin/bash

fusermount -u ~/storage_a

fusermount -u ~/storage_private_docs

sudo ~/bin/luks_umount.sh /dev/nvme1n1

sudo ~/bin/luks_umount.sh /dev/nvme2n1
