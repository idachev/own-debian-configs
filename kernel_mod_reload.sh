#!/bin/bash

MOD_NAME=${1}

echo -e "Reload kernal mod: ${MOD_NAME}"

sudo rmmod ${MOD_NAME}

sleep 5

sudo modprobe ${MOD_NAME}

echo -e "Reload DONE"

