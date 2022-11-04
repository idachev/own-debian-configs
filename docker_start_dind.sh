#!/usr/bin/env bash

set -e

docker run --privileged -d --network host -e DOCKER_TLS_CERTDIR -u 0 --name dind docker:dind

docker logs -f dind

