#!/bin/bash

fusermount -u ~/storage_a

fusermount -u ~/storage_private_docs

fusermount -u ~/storage/crypt

sudo ~/bin/luks_umount.sh /dev/sda

