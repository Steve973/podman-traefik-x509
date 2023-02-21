#!/bin/bash

# App versions
MONGO_VERSION=6.0.3
ARANGO_VERSION=3.10.2
ELK_VERSION=8.5.3
GRAFANA_VERSION=9.3.2
TRAEFIK_VERSION=2.9.6

# Ports
DATA_DASHBOARD_PORT=8444
SERVICES_INGRESS_PORT=8443
MONGO_PORT=27017
ARANGO_ROOT_PASSWORD=test123
ARANGO_PORT=8529
ELASTIC_PASSWORD=test123
ELASTIC_PORT=9200
KIBANA_PASSWORD=test123
KIBANA_PORT=5601
GRAFANA_PORT=3000
WORK_DIR=/tmp

systemctl --user status podman.socket &>/dev/null || systemctl --user start podman.socket

create_certs() {
  if [ ! -d ${WORK_DIR}/certs ]; then
    sh ./generate-certs.sh ${WORK_DIR}
  fi
}

create_secrets() {
  declare -A secrets=(
    [test-crt]="${WORK_DIR}"/certs/test.crt
    [test-key]="${WORK_DIR}"/certs/test.key
    [trust-pem]="${WORK_DIR}"/certs/myCA.pem
  )
  for secret_name in "${!secrets[@]}"; do
    podman secret ls --format "{{.Name}}" | grep "${secret_name}" || \
    podman secret create --driver=file "${secret_name}" "${secrets[${secret_name}]}"
  done
}

create_data_network() {
  podman network create data_network
}

remove_data_network() {
  podman network rm data_network
}

create_services_network() {
  podman network create services_network
}

remove_services_network() {
  podman network rm services_network
}

provision_data_resources() {
  create_certs
  init_mongodb
  init_arangodb
  init_elasticsearch
}

start_greeting_service() {
  podman pod create \
   --name greeting-service \
   --infra-name greeting-service-infra \
   --network services_network

  podman run -d \
   --name greeting-service1 \
   --pod greeting-service \
   --label "stackId=services" \
   --label "traefik.enable=true" \
   --label "traefik.http.routers.greeting-service-router.entrypoints=websecure" \
   --label "traefik.http.routers.greeting-service-router.rule=Host(\`localhost\`) && PathPrefix(\`/greeting-service\`)" \
   --label "traefik.http.routers.greeting-service-router.tls.options=default" \
   --label "traefik.http.services.greeting-service.loadbalancer.server.port=8080" \
   docker.io/library/greeting-service
}

stop_greeting_service() {
  podman container stop greeting-service1
  podman container rm greeting-service1
  podman pod stop greeting-service
  podman pod rm greeting-service
}

init_mongodb() {
  if [ ! -d ${WORK_DIR}/mongodb ]; then
    mkdir -p "${WORK_DIR}"/mongodb/configdb
    mkdir -p "${WORK_DIR}"/mongodb/db
    podman run -d \
     --name mongodb \
     --volume ${WORK_DIR}/mongodb/db:/data/db:Z \
     --env "MONGO_INITDB_ROOT_USERNAME=root" \
     --env "MONGO_INITDB_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}" \
     --env "MONGO_INITDB_DATABASE=admin" \
     --publish ${MONGO_PORT}:${MONGO_PORT} \
     --userns keep-id \
     docker.io/mongo:${MONGO_VERSION} \
      --bind_ip_all \
      --enableFreeMonitoring off
    sleep 10
    echo "MongoDB initialization complete"
    podman container stop mongodb
    podman container rm mongodb
  fi
}

start_mongodb() {
  podman pod create \
   --name mongodb \
   --infra-name mongodb-infra \
   --userns keep-id \
   --network data_network

  podman run -d \
   --name data_mongodb \
   --pod mongodb \
   --volume ${WORK_DIR}/mongodb/db:/data/db:Z \
   --label "stackId=data" \
   --label "traefik.enable=true" \
   --label "traefik.tcp.routers.mongodb-router.entrypoints=mongo-tcp" \
   --label "traefik.tcp.routers.mongodb-router.rule=HostSNI(\`localhost\`)" \
   --label "traefik.tcp.routers.mongodb-router.service=mongodb" \
   --label "traefik.tcp.routers.mongodb-router.tls=true" \
   --label "traefik.tcp.routers.mongodb-router.tls.options=default" \
   --label "traefik.tcp.services.mongodb.loadbalancer.server.port=${MONGO_PORT}" \
   docker.io/mongo:${MONGO_VERSION} \
    --quiet \
    --bind_ip_all \
    --auth \
    --enableFreeMonitoring off \
    --journal
}

stop_mongodb() {
  podman container stop data_mongodb
  podman container rm data_mongodb
  podman pod stop mongodb
  podman pod rm mongodb
}

init_arangodb() {
  if [ ! -d ${WORK_DIR}/arangodb ]; then
    mkdir -p ${WORK_DIR}/arangodb/apps
    mkdir -p ${WORK_DIR}/arangodb/data
  fi
}

start_arangodb() {
  podman pod create \
   --name arangodb \
   --infra-name arangodb-infra \
   --userns keep-id \
   --network data_network

  podman run -d \
   --name data_arangodb \
   --pod arangodb \
   --volume ${WORK_DIR}/arangodb/data:/var/lib/arangodb3:Z \
   --volume ${WORK_DIR}/arangodb/apps:/var/lib/arangodb3-apps:Z \
   --env ARANGO_ROOT_PASSWORD=${ARANGO_ROOT_PASSWORD} \
   --label "stackId=data" \
   --label "traefik.enable=true" \
   --label "traefik.http.routers.arangodb-router.entrypoints=arango-http" \
   --label "traefik.http.routers.arangodb-router.rule=Host(\`localhost\`)" \
   --label "traefik.http.routers.arangodb-router.service=arangodb" \
   --label "traefik.http.routers.arangodb-router.tls=true" \
   --label "traefik.http.routers.arangodb-router.tls.options=default" \
   --label "traefik.http.services.arangodb.loadbalancer.server.port=${ARANGO_PORT}" \
   docker.io/arangodb:${ARANGO_VERSION}
}

stop_arangodb() {
  podman container stop data_arangodb
  podman container rm data_arangodb
  podman pod stop arangodb
  podman pod rm arangodb
}

init_elasticsearch() {
  if [ ! -d ${WORK_DIR}/elasticsearch ]; then
    mkdir -p "${WORK_DIR}"/elasticsearch/data
    podman run -d \
     --name es01 \
     --volume ${WORK_DIR}/elasticsearch/data:/usr/share/elasticsearch/data:Z \
     --env discovery.type=single-node \
     --env ELASTIC_PASSWORD=${ELASTIC_PASSWORD} \
     --env xpack.security.enabled=true \
     --publish ${ELASTIC_PORT}:${ELASTIC_PORT} \
     --userns keep-id \
     docker.io/elasticsearch:${ELK_VERSION}
    echo "Waiting for Elasticsearch availability"
    until curl -s http://localhost:${ELASTIC_PORT} | grep -q "missing authentication credentials"; do
      sleep 10
    done
    echo "Setting kibana_system password"
    until curl -s -X POST -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" http://localhost:${ELASTIC_PORT}/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do
      sleep 10
    done
    echo "Elasticsearch initialization complete"
    podman container stop es01
    podman container rm es01
  fi
}

start_elasticsearch() {
  podman pod create \
   --name elasticsearch01 \
   --infra-name elasticsearch-infra \
   --userns keep-id \
   --network data_network

  podman run -d \
   --pod elasticsearch01 \
   --name es01 \
   --volume ${WORK_DIR}/elasticsearch/data:/usr/share/elasticsearch/data:Z \
   --env discovery.type=single-node \
   --env ELASTIC_PASSWORD=${ELASTIC_PASSWORD} \
   --env xpack.security.enabled=true \
   --label "stackId=data" \
   --label "traefik.enable=true" \
   --label "traefik.http.routers.elasticsearch-router.entrypoints=elasticsearch-http" \
   --label "traefik.http.routers.elasticsearch-router.rule=Host(\`localhost\`)" \
   --label "traefik.http.routers.elasticsearch-router.service=elasticsearch" \
   --label "traefik.http.routers.elasticsearch-router.tls=true" \
   --label "traefik.http.routers.elasticsearch-router.tls.options=default" \
   --label "traefik.http.services.elasticsearch.loadbalancer.server.port=${ELASTIC_PORT}" \
   docker.io/elasticsearch:${ELK_VERSION}
}

stop_elasticsearch() {
  podman container stop es01
  podman container rm es01
  podman pod stop elasticsearch01
  podman pod rm elasticsearch01
}

start_kibana() {
  podman pod create \
   --name kibana \
   --infra-name kibana-infra \
   --network data_network

  podman run -d \
   --name kibana1 \
   --pod kibana \
   --env SERVERNAME=kibana \
   --env ELASTICSEARCH_HOSTS=http://elasticsearch01:${ELASTIC_PORT} \
   --env ELASTICSEARCH_USERNAME=kibana_system \
   --env ELASTICSEARCH_PASSWORD=${KIBANA_PASSWORD} \
   --label "stackId=data" \
   --label "traefik.enable=true" \
   --label "traefik.http.routers.kibana-router.entrypoints=kibana-http" \
   --label "traefik.http.routers.kibana-router.rule=Host(\`localhost\`)" \
   --label "traefik.http.routers.kibana-router.service=kibana" \
   --label "traefik.http.routers.kibana-router.tls=true" \
   --label "traefik.http.routers.kibana-router.tls.options=default" \
   --label "traefik.http.services.kibana.loadbalancer.server.port=${KIBANA_PORT}" \
   docker.io/kibana:${ELK_VERSION}
}

stop_kibana() {
  podman container stop kibana1
  podman container rm kibana1
  podman pod stop kibana
  podman pod rm kibana
}

start_grafana() {
  podman pod create \
   --name grafana \
   --infra-name grafana-infra \
   --network data_network

  podman run -d \
   --name grafana1 \
   --pod grafana \
   --label "stackId=data" \
   --label "traefik.enable=true" \
   --label "traefik.http.routers.grafana-router.entrypoints=grafana-http" \
   --label "traefik.http.routers.grafana-router.rule=Host(\`localhost\`)" \
   --label "traefik.http.routers.grafana-router.service=grafana" \
   --label "traefik.http.routers.grafana-router.tls=true" \
   --label "traefik.http.routers.grafana-router.tls.options=default" \
   --label "traefik.http.services.grafana.loadbalancer.server.port=${GRAFANA_PORT}" \
   docker.io/grafana/grafana:${GRAFANA_VERSION}
}

stop_grafana() {
  podman container stop grafana1
  podman container rm grafana1
  podman pod stop grafana
  podman pod rm grafana
}

start_data_proxy() {
  podman pod create \
   --name data_proxy \
   --infra-name data-proxy-infra \
   --network data_network \
   --publish ${DATA_DASHBOARD_PORT}:${DATA_DASHBOARD_PORT} \
   --publish ${MONGO_PORT}:${MONGO_PORT} \
   --publish ${ARANGO_PORT}:${ARANGO_PORT} \
   --publish ${ELASTIC_PORT}:${ELASTIC_PORT} \
   --publish ${KIBANA_PORT}:${KIBANA_PORT} \
   --publish ${GRAFANA_PORT}:${GRAFANA_PORT}

  podman run -d \
   --name traefik_proxy_data \
   --pod data_proxy \
   --secret source=test-crt,target=/certs/test.crt,type=mount \
   --secret source=test-key,target=/certs/test.key,type=mount \
   --secret source=trust-pem,target=/certs/trust.pem,type=mount \
   --volume ./traefik/data/config:/etc/traefik/dynamic:Z \
   --volume ./traefik/data/credentials.txt:/etc/credentials.txt:Z \
   --volume "${XDG_RUNTIME_DIR}"/podman/podman.sock:/var/run/docker.sock \
   --label "stackId=data" \
   --label "traefik.enable=true" \
   --label "traefik.http.routers.dashboard.entrypoints=websecure" \
   --label "traefik.http.routers.dashboard.rule=HostRegexp(\`data.{name:.+}\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))" \
   --label "traefik.http.routers.dashboard.tls=true" \
   --label "traefik.http.routers.dashboard.tls.options=default" \
   --label "traefik.http.routers.dashboard.service=api@internal" \
   --label "traefik.http.routers.dashboard.middlewares=dashboard-auth" \
   --label "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/etc/credentials.txt" \
   docker.io/traefik:${TRAEFIK_VERSION} \
    --global.checkNewVersion=false \
    --global.sendAnonymousUsage=false \
    --accessLog=true \
    --accessLog.format=json \
    --api=true \
    --api.dashboard=true \
    --entrypoints.websecure.address=:${DATA_DASHBOARD_PORT} \
    --entrypoints.mongo-tcp.address=:${MONGO_PORT} \
    --entrypoints.arango-http.address=:${ARANGO_PORT} \
    --entrypoints.elasticsearch-http.address=:${ELASTIC_PORT} \
    --entrypoints.kibana-http.address=:${KIBANA_PORT} \
    --entrypoints.grafana-http.address=:${GRAFANA_PORT} \
    --providers.docker=true \
    --providers.docker.exposedbydefault=false \
    --providers.docker.network=data_network \
    --providers.docker.constraints=Label\(\`stackId\`,\`data\`\) \
    --providers.file.directory=/etc/traefik/dynamic
}

stop_data_proxy() {
  podman container stop traefik_proxy_data
  podman container rm traefik_proxy_data
  podman pod stop data_proxy
  podman pod rm data_proxy
}

start_services_proxy() {
  podman pod create \
   --name services_proxy \
   --infra-name services-proxy-infra \
   --network services_network \
   --publish ${SERVICES_INGRESS_PORT}:${SERVICES_INGRESS_PORT}
  podman run -d \
   --name traefik_proxy_services \
   --pod services_proxy \
   --secret source=test-crt,target=/certs/test.crt,type=mount \
   --secret source=test-key,target=/certs/test.key,type=mount \
   --secret source=trust-pem,target=/certs/trust.pem,type=mount \
   --volume ./traefik/services/config:/etc/traefik/dynamic:Z \
   --volume ./traefik/services/credentials.txt:/etc/credentials.txt:Z \
   --volume "${XDG_RUNTIME_DIR}"/podman/podman.sock:/var/run/docker.sock \
   --label "stackId=services" \
   --label "traefik.enable=true" \
   --label "traefik.http.routers.dashboard.entrypoints=websecure" \
   --label "traefik.http.routers.dashboard.rule=Host(\`services.localhost\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))" \
   --label "traefik.http.routers.dashboard.tls.options=default" \
   --label "traefik.http.routers.dashboard.service=api@internal" \
   --label "traefik.http.routers.dashboard.middlewares=dashboard-auth" \
   --label "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/etc/credentials.txt" \
   docker.io/traefik:${TRAEFIK_VERSION} \
    --global.checkNewVersion=false \
    --global.sendAnonymousUsage=false \
    --accessLog=true \
    --accessLog.format=json \
    --api=true \
    --api.dashboard=true \
    --entrypoints.websecure.address=:${SERVICES_INGRESS_PORT} \
    --entrypoints.websecure.http.middlewares=pass-tls-client-cert@file \
    --providers.docker=true \
    --providers.docker.exposedbydefault=false \
    --providers.docker.network=services_network \
    --providers.docker.constraints=Label\(\`stackId\`,\`services\`\) \
    --providers.file.directory=/etc/traefik/dynamic \
    --serversTransport.insecureSkipVerify=true
}

stop_services_proxy() {
  podman container stop traefik_proxy_services
  podman container rm traefik_proxy_services
  podman pod stop services_proxy
  podman pod rm services_proxy
}

start_data_apps() {
  start_mongodb
  start_arangodb
  start_elasticsearch
  start_kibana
  start_grafana
}

stop_data_apps() {
  stop_mongodb
  stop_arangodb
  stop_elasticsearch
  stop_kibana
  stop_grafana
}

start_services_apps() {
  start_greeting_service
}

stop_services_apps() {
  stop_greeting_service
}

start_data_stack() {
  create_secrets
  provision_data_resources
  create_data_network
  start_data_apps
  start_data_proxy
}

stop_data_stack() {
  stop_data_apps
  stop_data_proxy
  remove_data_network
}

start_services_stack() {
  create_secrets
  create_services_network
  start_services_apps
  start_services_proxy
}

stop_services_stack() {
  stop_services_apps
  stop_services_proxy
  remove_services_network
}

start_all() {
  start_data_stack
  start_services_stack
}

stop_all() {
  stop_services_stack
  stop_data_stack
}

clean_resources() {
  pushd ${WORK_DIR} || return
  rm -rf certs/ mongodb/ arangodb/ elasticsearch/
  popd || exit
}

TEMP=$(getopt -o cs:t: --long clean,start:,stop: -- "$@")
eval set -- "${TEMP}"
case "$1" in
  -c|--clean)
    target=clean_resources
    ;;
  -s|--start)
    case "$2" in
      'data')
        target=start_data_stack
        ;;
      'services')
        target=start_services_stack
        ;;
      'all')
        target=start_all
        ;;
    esac
    ;;
  -t|--stop)
    case "$2" in
      'data')
        target=stop_data_stack
        ;;
      'services')
        target=stop_services_stack
        ;;
      'all')
        target=stop_all
        ;;
    esac
    ;;
  *) echo "Invalid option selected!"
    exit 1
    ;;
esac

eval "${target}"
