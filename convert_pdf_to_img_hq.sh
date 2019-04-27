#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}"/_bash_utils.sh

IN_PDF=${1}
if [[ ! -f "${IN_PDF}" ]]; then
  log_err "Expected valid input pdf: ${IN_PDF}"
  exit 1
fi

OUT_IMG=${2}
if [[ -z "${OUT_IMG}" ]]; then
  log_err "Expected valid output image file: ${OUT_IMG}"
  exit 1
fi

RESIZE=${3}
if [[ ! -z "${RESIZE}" ]]; then
  RESIZE="-resize ${RESIZE}"
  log "Using ${RESIZE}"
fi

convert \
  -verbose \
  -density 150 \
  -trim \
  "${IN_PDF}" \
  -quality 95 \
  -flatten \
  -sharpen 0x1.0 \
  -trim \
  ${RESIZE} \
  "${OUT_IMG}"

log "Conversion done:"
ls -alh "${OUT_IMG}"
