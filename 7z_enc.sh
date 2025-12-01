#!/bin/bash

archive=$1
shift
# Maximum compression with encryption
# -mhe=on - Encrypt headers (hides filenames)
# -mfb=273 - Maximum fast bytes for LZMA
# -md=128m - Dictionary size 128MB (better compression, requires more RAM)
# -snl - Store symbolic links as links (preserves symlinks)
7z a -bd -bb1 -mhe=on -p"${PASSWORD_7Z}" -t7z -m0=lzma2 -mx=9 -mfb=273 -md=128m -ms=on -mmt=on -snl "$archive" "$@"
