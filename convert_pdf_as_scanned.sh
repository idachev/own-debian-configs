#!/bin/bash

convert "$1" \
  -density 300 \
  -colorspace gray \( +clone -blur 0x2 \) \
  +swap -compose divide -composite \
  -linear-stretch 2%x2% \
  "$2"
