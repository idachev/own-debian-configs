#!/bin/bash

# git automatically preappend its own LD lib path which messup aws-vault
export LD_LIBRARY_PATH=/usr/lib/oracle/12.1/client64/lib

aws-vault $@   

