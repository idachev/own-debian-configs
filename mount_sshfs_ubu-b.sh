#!/bin/bash

LOCAL_DIR=~/sshfs/idachev-ubu-b

if [ ! -d $LOCAL_DIR ]; then
	mkdir -p $LOCAL_DIR
fi

echo
echo "To unmount use: fusermount -u $LOCAL_DIR"

`ssh-add -l | grep -q id_dsa_a`
if [ $? -ne 0 ]; then
  ssh-add ~/.ssh/id_dsa_a
fi

sshfs -o idmap=user "idachev@idachev-ubu-b:/" $LOCAL_DIR

