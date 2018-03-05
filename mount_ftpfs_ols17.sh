#!/bin/bash

LOCAL_DIR=~/sshfs/ols17

if [ ! -d $LOCAL_DIR ]; then
	mkdir -p $LOCAL_DIR
fi

echo
echo "To unmount use: fusermount -u $LOCAL_DIR"

curlftpfs -o uid=`id -u $USER` -o gid=`id -g $USER` -o user="idachev" "ols17.com" $LOCAL_DIR
