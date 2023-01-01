#!/bin/bash

##### source ./.env
MONGO_ROOT_PASSWORD=test123

podman run -d \
 --name mongodb \
 --volume ./mongodb/db:/data/db:z \
 --env "MONGO_INITDB_ROOT_USERNAME=root" \
 --env "MONGO_INITDB_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}" \
 --env "MONGO_INITDB_DATABASE=admin" \
 --publish 27017:27017 \
 --userns keep-id \
 docker.io/mongo:6.0.3 \
  --bind_ip_all \
  --enableFreeMonitoring off

sleep 10

echo "MongoDB initialization complete"

podman container stop mongodb
podman container rm mongodb
