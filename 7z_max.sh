#!/bin/bash

archive=$1
shift

# Check examples here http://www.dotnetperls.com/7-zip-examples
# -mmt=on - Enable multithreading
# -ms=on - Enable solid mode. In this case you could not update the archive.
# -r - Used to recursivlly add files matching filter given at the end of commands.
#      If you give ./*.txt then it will add all text files from all sub directories.
# -mfb=273 - Maximum fast bytes for LZMA (max compression)
# -md=128m - Dictionary size 128MB (increase for better compression, requires more RAM)
# -snl - Store symbolic links as links (preserves symlinks)

7z a -bd -t7z -m0=lzma2 -mx=9 -mfb=273 -md=128m -ms=on -mmt=on -snl -r "$archive" "$@"

