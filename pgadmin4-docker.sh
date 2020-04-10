#!/bin/bash

docker run --name pgadmin \
  --net host \
  -e "PGADMIN_DEFAULT_EMAIL=admin@test.com" \
  -e "PGADMIN_DEFAULT_PASSWORD=admin" \
  -e "PGADMIN_LISTEN_PORT=17080" \
  -d -it \
  dpage/pgadmin4

