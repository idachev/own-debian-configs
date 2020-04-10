#!/bin/bash

ssh -o ConnectTimeout=30 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -n -f -N -L $* 

