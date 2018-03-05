#!/bin/bash

for var in "$@"; do
  convert "$var" -monochrome  "$var"
  echo "monochrome: $var"
done


