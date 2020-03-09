#!/bin/bash

gs -dNOPAUSE -dBATCH -dFirstPage=2 -dLastPage=2 -sDEVICE=pdfwrite \
    -sOutputFile=dest.pdf -f src.pdf

