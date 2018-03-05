#!/bin/bash

LOCAL_DIR=~/sshfs/bstorage

if [ ! -d $LOCAL_DIR ]; then
	mkdir -p $LOCAL_DIR
fi

echo
echo "To unmount use: fusermount -u $LOCAL_DIR"

sshfs -o idmap=user "idachev@bstorage-01.unix-it.net:/home/idachev" $LOCAL_DIR

#echo "Need to run: ssh tunnel-bstorage"
#sshfs -o idmap=user "bstorage:/home/idachev" $LOCAL_DIR

