#!/bin/bash

LOCAL_DIR=~/ftpfs/lz2gl

if [ ! -d $LOCAL_DIR ]; then
	mkdir -p $LOCAL_DIR
fi

echo
echo "To unmount use: fusermount -u $LOCAL_DIR"
read -s -p "password: " passw;echo
echo "Connecting..."
curlftpfs -o uid=`id -u $USER` -o gid=`id -g $USER` "lz2glco:$passw@ftp.lz2gl.com" $LOCAL_DIR

