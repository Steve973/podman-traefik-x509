#!/bin/bash

if [ ! -d ./certs ]; then
  sh ./generate-certs.sh
fi

podman secret create --driver=file test-crt ./certs/test.crt
podman secret create --driver=file test-key ./certs/test.key
podman secret create --driver=file trust-pem ./certs/myCA.pem

podman network create data_network

##### source ./.env
ARANGO_ROOT_PASSWORD=test123
ARANGO_PORT=8529
ELASTIC_PASSWORD=test123
ELASTIC_PORT=9200
KIBANA_PASSWORD=test123
KIBANA_PORT=5601
GRAFANA_PORT=3000

podman pod create \
 --name arangodb \
 --infra-name arangodb-infra \
 --userns keep-id \
 --network data_network

podman pod create \
 --name elasticsearch01 \
 --infra-name elasticsearch-infra \
 --userns keep-id \
 --network data_network

podman pod create \
 --name kibana \
 --infra-name kibana-infra \
 --network data_network

podman pod create \
 --name grafana \
 --infra-name grafana-infra \
 --network data_network

podman pod create \
 --name data_proxy \
 --infra-name data-proxy-infra \
 --network data_network \
 --publish 8444:8444 \
 --publish ${ARANGO_PORT}:${ARANGO_PORT} \
 --publish ${ELASTIC_PORT}:${ELASTIC_PORT} \
 --publish ${KIBANA_PORT}:${KIBANA_PORT} \
 --publish ${GRAFANA_PORT}:${GRAFANA_PORT}

podman run -d \
 --name data_arangodb \
 --pod arangodb \
 --volume ./arangodb/data:/var/lib/arangodb3:z \
 --volume ./arangodb/apps:/var/lib/arangodb3-apps:z \
 --env ARANGO_ROOT_PASSWORD=${ARANGO_ROOT_PASSWORD} \
 --label "stackId=data" \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.arangodb-router.entrypoints=arango-tcp" \
 --label "traefik.http.routers.arangodb-router.rule=Host(\`localhost\`)" \
 --label "traefik.http.routers.arangodb-router.service=arangodb" \
 --label "traefik.http.routers.arangodb-router.tls=true" \
 --label "traefik.http.routers.arangodb-router.tls.options=default" \
 --label "traefik.http.services.arangodb.loadbalancer.server.port=${ARANGO_PORT}" \
 docker.io/arangodb:3.10.2

podman run -d \
 --pod elasticsearch01 \
 --name es01 \
 --volume ./elasticsearch/data:/usr/share/elasticsearch/data:z \
 --env discovery.type=single-node \
 --env ELASTIC_PASSWORD=${ELASTIC_PASSWORD} \
 --env xpack.security.enabled=true \
 --label "stackId=data" \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.elasticsearch-router.entrypoints=elasticsearch-tcp" \
 --label "traefik.http.routers.elasticsearch-router.rule=Host(\`localhost\`)" \
 --label "traefik.http.routers.elasticsearch-router.service=elasticsearch" \
 --label "traefik.http.routers.elasticsearch-router.tls=true" \
 --label "traefik.http.routers.elasticsearch-router.tls.options=default" \
 --label "traefik.http.services.elasticsearch.loadbalancer.server.port=${ELASTIC_PORT}" \
 docker.io/elasticsearch:8.5.3

podman run -d \
 --name kibana1 \
 --pod kibana \
 --env SERVERNAME=kibana \
 --env ELASTICSEARCH_HOSTS=http://elasticsearch01:9200 \
 --env ELASTICSEARCH_USERNAME=kibana_system \
 --env ELASTICSEARCH_PASSWORD=${KIBANA_PASSWORD} \
 --label "stackId=data" \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.kibana-router.entrypoints=kibana-tcp" \
 --label "traefik.http.routers.kibana-router.rule=Host(\`localhost\`)" \
 --label "traefik.http.routers.kibana-router.service=kibana" \
 --label "traefik.http.routers.kibana-router.tls=true" \
 --label "traefik.http.routers.kibana-router.tls.options=default" \
 --label "traefik.http.services.kibana.loadbalancer.server.port=${KIBANA_PORT}" \
 docker.io/kibana:8.5.3

podman run -d \
 --name grafana1 \
 --pod grafana \
 --label "stackId=data" \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.grafana-router.entrypoints=grafana-tcp" \
 --label "traefik.http.routers.grafana-router.rule=Host(\`localhost\`)" \
 --label "traefik.http.routers.grafana-router.service=grafana" \
 --label "traefik.http.routers.grafana-router.tls=true" \
 --label "traefik.http.routers.grafana-router.tls.options=default" \
 --label "traefik.http.services.grafana.loadbalancer.server.port=${GRAFANA_PORT}" \
 docker.io/grafana/grafana:9.3.2

podman run -d \
 --name traefik_proxy_data \
 --pod data_proxy \
 --secret source=test-crt,target=/certs/test.crt,type=mount \
 --secret source=test-key,target=/certs/test.key,type=mount \
 --secret source=trust-pem,target=/certs/trust.pem,type=mount \
 --volume ./traefik/data/config:/etc/traefik/dynamic:Z \
 --volume ./traefik/data/credentials.txt:/etc/credentials.txt:Z\
 --volume /run/user/1000/podman/podman.sock:/var/run/docker.sock \
 --label "stackId=data" \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.dashboard.entrypoints=websecure" \
 --label "traefik.http.routers.dashboard.rule=Host(\`data.localhost\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))" \
 --label "traefik.http.routers.dashboard.tls.options=default" \
 --label "traefik.http.routers.dashboard.service=api@internal" \
 --label "traefik.http.routers.dashboard.middlewares=dashboard-auth" \
 --label "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/etc/credentials.txt" \
 docker.io/traefik:2.9.6 \
  --global.checkNewVersion=false \
  --global.sendAnonymousUsage=false \
  --accessLog=true \
  --accessLog.format=json \
  --api=true \
  --api.dashboard=true \
  --entrypoints.websecure.address=:8444 \
  --entrypoints.arango-tcp.address=:${ARANGO_PORT} \
  --entrypoints.elasticsearch-tcp.address=:${ELASTIC_PORT} \
  --entrypoints.kibana-tcp.address=:${KIBANA_PORT} \
  --entrypoints.grafana-tcp.address=:${GRAFANA_PORT} \
  --providers.docker=true \
  --providers.docker.exposedbydefault=false \
  --providers.docker.network=data_network \
  --providers.docker.constraints=Label\(\`stackId\`,\`data\`\) \
  --providers.file.directory=/etc/traefik/dynamic
