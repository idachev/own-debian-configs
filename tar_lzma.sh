#!/bin/bash

ARCH_NAME=${1}
DIR=${2}

tar -cf ${ARCH_NAME}.tar.lzma -I 'lzma -6' ${DIR}

