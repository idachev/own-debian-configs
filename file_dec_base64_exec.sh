#!/bin/bash

IN_FILE=${1}

openssl enc -aes-256-cbc -d -a -in "${IN_FILE}" | bash -

