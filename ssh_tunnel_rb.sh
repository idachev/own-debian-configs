#!/bin/bash

ssh -o ConnectTimeout=10 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -n -f -N -L 7722:localhost:5522 ubuntu@rb.dev.datastork.io

