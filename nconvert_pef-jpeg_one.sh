#!/bin/bash

# nconvert is from ~/bin and is downloaded from XnView
# -raw_camerabalance -raw_autobright 
nconvert -out jpeg -q 100 -keepfiledate -high_res -raw_camerabalance -raw_autobright $1

# nconvert does not set the correct date under Linux
exiftool '-CreateDate>FileModifyDate' $1
 
