#!/bin/bash

USER_PATTERN="${1}"

git for-each-ref --format='%(committerdate) %09 %(authorname) %09 %(refname)' | grep -i -e "${USER_PATTERN}.*refs/remotes" | sort -k5n -k2M -k3n -k4n

