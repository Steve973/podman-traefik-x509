#!/bin/bash
if [ ! -d ./certs ]; then
  sh ./generate-certs.sh
fi

podman secret create --driver=file test-crt ./certs/test.crt
podman secret create --driver=file test-key ./certs/test.key
podman secret create --driver=file trust-pem ./certs/myCA.pem

podman network create services_network

podman pod create \
 --name proxy \
 --infra-name proxy-infra \
 --network services_network \
 --publish 8443:8443

podman pod create \
 --name greeting-service \
 --infra-name greeting-service-infra \
 --network services_network

podman run -d \
 --name greeting_service \
 --pod greeting-service \
 --label "traefik.enable=true" \
 --label "traefik.http.routers.greeting-service-router.entrypoints=websecure" \
 --label "traefik.http.routers.greeting-service-router.rule=HostRegexp(\`{catchall:.+}\`) && PathPrefix(\`/greeting-service\`)" \
 --label "traefik.http.routers.greeting-service-router.tls.options=default" \
 --label "traefik.http.services.greeting-service.loadbalancer.server.port=8080" \
 docker.io/library/greeting-service

podman run -d \
 --name traefik \
 --pod proxy \
 --secret source=test-crt,target=/certs/test.crt,type=mount \
 --secret source=test-key,target=/certs/test.key,type=mount \
 --secret source=trust-pem,target=/certs/trust.pem,type=mount \
 --volume ./traefik/config:/etc/traefik/dynamic:Z \
 --volume /run/user/1000/podman/podman.sock:/var/run/docker.sock \
 docker.io/traefik:2.9.6 \
  --global.checkNewVersion=false \
  --global.sendAnonymousUsage=false \
  --accessLog=true \
  --accessLog.format=json \
  --api=true \
  --api.dashboard=true \
  --api.insecure=true \
  --entrypoints.websecure.address=:8443 \
  --entrypoints.websecure.http.middlewares=pass-tls-client-cert@file \
  --providers.docker=true \
  --providers.docker.exposedbydefault=false \
  --providers.docker.network=services_network \
  --providers.file.directory=/etc/traefik/dynamic
  