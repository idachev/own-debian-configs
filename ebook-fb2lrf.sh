#!/bin/bash

ebook-convert $1 $2 --output-profile=sony300 --header --header-format='%a, "%t"' --no-inline-fb2-toc

