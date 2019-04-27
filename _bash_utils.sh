#!/bin/bash

function log() {
  echo -e "\n$(date -u --iso-8601=seconds) $1"
}

function log_err() {
  >&2 echo -e "\n$(date -u --iso-8601=seconds) $1"
}
