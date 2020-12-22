#!/bin/bash

DIR=$1
DATE=$2

find "${DIR}" -type f -newermt "${DATE}" -print0 | ifne xargs -0 stat -c '%y %n %A %U(%u):%G(%g) size: %s'

