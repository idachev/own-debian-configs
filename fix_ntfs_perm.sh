#!/bin/sh

ARGS=1                 # Expect one command-line argument.
if [ $# -ne "$ARGS" ]  # If not 1 arg...
then
  directory=`pwd`      # current working directory
else
  directory=$1
fi

chmod -R go-rwx "$directory"
find "$directory" -type f -print0 | xargs -0 chmod u-x

