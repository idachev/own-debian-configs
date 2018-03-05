#!/bin/sh

cat $1 | openssl des3 -d -salt | tar -xvz
