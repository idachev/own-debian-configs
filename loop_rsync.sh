#!/bin/bash

i=1
c12=0
while [ $i -eq 1 ]
do

# --bwlimit=128 
rsync -FavvP --timeout=20 --contimeout=60 --password-file=$1 $2 $3
err=$?

# check if rsync finish with no error
if [ $err -eq 0 ]; then
  i=0
  break
fi

echo;echo;echo
date
echo "rsync exit with error: $err"

# In case it is protocol data stream (code 12) then sleep 30s always
ERR_12_TIMEOUT=90
ERR_12_TIMES=5
if [ $err -eq 12 ]; then
  c12=$(($c12+1))
  if [ $c12 -ge $ERR_12_TIMES ]; then
    echo "Found protocol data stream error $c12 times, sleep ${ERR_12_TIMEOUT}s ...";
    sleep $ERR_12_TIMEOUT;
    c12=0
  fi
else
  c12=0
fi

# Sleep random seconds
t=$((($RANDOM%10)+5))
echo "Sleep for ${t}s ..."
sleep $t

done

