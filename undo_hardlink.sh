#!/bin/bash

while [ -n "$*" ];do
  TMPNAME=$(mktemp)
  cp -a "$1" $TMPNAME
  if [ $? == 0 ];then
    rm "$1"
    mv $TMPNAME "$1"
  fi
  shift
done

