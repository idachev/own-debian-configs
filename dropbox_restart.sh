#!/bin/bash

dropbox stop

sleep 1

dropbox start

sleep 1

cpunice.sh dropbox 1 70

