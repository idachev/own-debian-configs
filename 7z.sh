#!/bin/sh

archive=$1
shift
7z a -bd -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$archive" "$@"

