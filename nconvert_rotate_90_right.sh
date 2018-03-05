#!/bin/bash

# nconvert is from ~/bin and is downloaded from XnView
nconvert -overwrite -q 100 -keepfiledate -rotate 90 $1

# nconvert does not set the correct date under Linux
exiftool '-CreateDate>FileModifyDate' $1

