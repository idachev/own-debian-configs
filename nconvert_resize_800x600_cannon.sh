#!/bin/bash

RS_DIR=800x600

mkdir $RS_DIR

cp *.jpg $RS_DIR

cd $RS_DIR

# nconvert is from ~/bin and is downloaded from XnView
nconvert -keepfiledate -overwrite -rflag orient -resize 800 600 *.*

# nconvert does not set the correct date under Linux
exiftool '-CreateDate>FileModifyDate' *.jpg

