#!/bin/bash

DST=$1
shift

gs -dNOPAUSE -sDEVICE=pdfwrite -sOUTPUTFILE="${DST}" -dBATCH $*

