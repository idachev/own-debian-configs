#!/bin/bash

INPUT_FILE=${1}
ERROR_LOG="${INPUT_FILE}-error.log"

echo "Find errors in ${ERROR_LOG}"
ffmpeg -v error -i "${INPUT_FILE}" -f null - 2>${ERROR_LOG}
