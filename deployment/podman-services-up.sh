#!/bin/bash

if [ ! -d ./certs ]; then
  sh ./generate-certs.sh
fi

podman secret create --driver=file test-crt ./certs/test.crt
podman secret create --driver=file test-key ./certs/test.key
podman secret create --driver=file trust-pem ./certs/myCA.pem

podman network create services_network

podman pod create \
 --name services_proxy \
 --infra-name services-proxy-infra \
 --network services_network \
 --publish 8443:8443

podman pod create \
 --name greeting-service \
 --infra-name greeting-service-infra \
 --network services_network

podman run -d \
 --name greeting_service \
 --pod greeting-service \
 --label "stackId=services" \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.greeting-service-router.entrypoints=websecure" \
 --label "traefik.http.routers.greeting-service-router.rule=Host(\`localhost\`) && PathPrefix(\`/greeting-service\`)" \
 --label "traefik.http.routers.greeting-service-router.tls.options=default" \
 --label "traefik.http.services.greeting-service.loadbalancer.server.port=8080" \
 docker.io/library/greeting-service

podman run -d \
 --name traefik_proxy_services \
 --pod services_proxy \
 --secret source=test-crt,target=/certs/test.crt,type=mount \
 --secret source=test-key,target=/certs/test.key,type=mount \
 --secret source=trust-pem,target=/certs/trust.pem,type=mount \
 --volume ./traefik/services/config:/etc/traefik/dynamic:Z \
 --volume ./traefik/services/credentials.txt:/etc/credentials.txt:Z\
 --volume /run/user/1000/podman/podman.sock:/var/run/docker.sock \
 --label "stackId=services" \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.dashboard.entrypoints=websecure" \
 --label "traefik.http.routers.dashboard.rule=Host(\`services.localhost\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))" \
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
  --entrypoints.websecure.address=:8443 \
  --entrypoints.websecure.http.middlewares=pass-tls-client-cert@file \
  --providers.docker=true \
  --providers.docker.exposedbydefault=false \
  --providers.docker.network=services_network \
  --providers.docker.constraints=Label\(\`stackId\`,\`services\`\) \
  --providers.file.directory=/etc/traefik/dynamic \
  --serversTransport.insecureSkipVerify=true
