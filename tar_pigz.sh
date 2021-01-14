#!/bin/bash

ARCH_NAME=${1}
DIR=${2}

tar -cf "${ARCH_NAME}" -I 'pigz -9' "${DIR}"
