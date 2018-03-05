#!/bin/bash

SRV_OLS="ols15.com"
USER_OLS="ivand"

SOURCE=$2
if [ ! -d $SOURCE ]; then
	echo "Expected source to be existing directory!"
	exit 1
fi

NAME=$3

BASEDIR=$(dirname $0)

if [ $1 = "fullenc" ]; then
	SYNC_CMD="full"
	echo
	echo '========================================'
	echo 'Call encfs_encdec.sh...'
	TARGET="$(mktemp -d)"
	$BASEDIR/encfs_encdec.sh -enc $SOURCE $TARGET
elif [ $1 = "full" ]; then
	SYNC_CMD="full"
	TARGET=$SOURCE
elif [ $1 = "incenc" ]; then
	SYNC_CMD="inc"
	echo
	echo '========================================'
	echo 'Call encfs_encdec.sh...'
	TARGET="$(mktemp -d)"
	$BASEDIR/encfs_encdec.sh -enc $SOURCE $TARGET
elif [ $1 = "inc" ]; then
	SYNC_CMD="inc"
	TARGET=$SOURCE
else
	echo "Expected first argument one of: fullenc, full, incenc or inc"
	exit 1
fi

echo
echo '========================================'
echo 'Call inc-rsync...'
# -d warning error info debug
inc-rsync -d debug -p "$BASEDIR/pass_ols.txt" -t "$USER_OLS@$SRV_OLS" 127.0.0.1:8873:127.0.0.1:873 -s "$BASEDIR/pass_ols.txt" $SYNC_CMD "$TARGET/" "rsync://$USER_OLS@127.0.0.1:8873/$USER_OLS/$NAME"

echo
echo '========================================'
echo 'Kill all encfs...'
killall encfs

