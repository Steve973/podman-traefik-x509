#!/bin/bash

##### source ./.env
ELASTIC_PASSWORD=test123
KIBANA_PASSWORD=test123

podman run -d \
 --name es01 \
 --volume ./elasticsearch/data:/usr/share/elasticsearch/data:z \
 --env discovery.type=single-node \
 --env ELASTIC_PASSWORD=${ELASTIC_PASSWORD} \
 --env xpack.security.enabled=true \
 --publish 9200:9200 \
 --userns keep-id \
 docker.io/elasticsearch:8.5.3

echo "Waiting for Elasticsearch availability"
until curl -s http://localhost:9200 | grep -q "missing authentication credentials"
do
  sleep 10
done

echo "Setting kibana_system password"
until curl -s -X POST -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" http://localhost:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"
do
  sleep 10
done

echo "Elasticsearch initialization complete"

podman container stop es01
podman container rm es01
