#!/bin/bash

FPAGE=$1
LPAGE=$2
SRC=$3
DST=$4

gs -dNOPAUSE -dBATCH -dFirstPage="${FPAGE}" -dLastPage="${LPAGE}" -sDEVICE=pdfwrite \
    -sOutputFile="${DST}" -f "${SRC}"

