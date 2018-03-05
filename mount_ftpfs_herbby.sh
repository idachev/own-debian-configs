#!/bin/bash

LOCAL_DIR=~/ftpfs/herbby

if [ ! -d $LOCAL_DIR ]; then
	mkdir -p $LOCAL_DIR
fi

echo
echo "To unmount use: fusermount -u $LOCAL_DIR"
echo "Connecting..."
curlftpfs -o uid=`id -u $USER` -o gid=`id -g $USER` "herbbyco@ftp.herbby.com" $LOCAL_DIR

