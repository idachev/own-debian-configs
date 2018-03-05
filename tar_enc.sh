#!/bin/sh

archive=$1
shift
tar -cz "$@" | openssl des3 -salt > $archive
