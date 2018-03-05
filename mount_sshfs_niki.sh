#!/bin/bash

LOCAL_DIR=~/sshfs/niki

if [ ! -d $LOCAL_DIR ]; then
	mkdir -p $LOCAL_DIR
fi

echo
echo "To unmount use: fusermount -u $LOCAL_DIR"

`ssh-add -l | grep -q id_dsa_a`
if [ $? -ne 0 ]; then
  ssh-add ~/.ssh/id_dsa_a
fi

sshfs -o idmap=user -p 443 "ivan@dachev.info:/storage/idachev" $LOCAL_DIR

