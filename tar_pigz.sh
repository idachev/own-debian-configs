#!/bin/bash

ARCH_NAME=${1}
DIR=${2}
EXCLUDE=${3}

tar -cf "${ARCH_NAME}" -I 'pigz -9' ${EXCLUDE} "${DIR}"

