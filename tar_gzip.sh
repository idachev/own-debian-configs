#!/bin/bash

ARCH_NAME=${1}
DIR=${2}

tar -cf ${ARCH_NAME}.tar.gz -I 'pigz -7' ${DIR}

