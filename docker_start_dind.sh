#!/usr/bin/env bash

docker rm dind
docker run --privileged -d --network host -e DOCKER_TLS_CERTDIR -u 0 --name dind docker:dind

