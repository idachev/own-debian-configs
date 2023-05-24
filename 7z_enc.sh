#!/bin/bash

archive=$1
shift
7z a -bd -mhe=on -p"${PASSWORD_7Z}" -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$archive" "$@"
