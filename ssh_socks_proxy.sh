#!/bin/bash
set -x

ssh -D 1337 -q -C -N -f ${*}

