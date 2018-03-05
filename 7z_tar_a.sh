#!/bin/bash

DIR_NAME=$1
ARCH_NAME=$2

time tar cf - "${DIR_NAME}" | 7za a -mmt=8 -mx=0 -si -v2g "${ARCH_NAME}".tar.7z

