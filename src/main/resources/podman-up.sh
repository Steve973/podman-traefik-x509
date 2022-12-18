#!/bin/bash
HOST=$(hostname)
if [ ! -d ./certs ]; then
  mkdir ./certs
  pushd ./certs

  # create the CA extension file
  cat > test.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName=@alt_names

[alt_names]
DNS.1=${HOST}
DNS.2=localhost
EOF

  # generate the local CA key
  openssl genrsa -out ./myCA.key 2048
  # generate the local CA cert
  openssl req -x509 -new -nodes -key ./myCA.key -sha384 -days 999 -out ./myCA.pem -subj "/C=XX/ST=Confusion/L=Somewhere/O=example/CN=CertificateAuthority"
  # create certificate signing request
  openssl req -newkey rsa:4096 -nodes -sha384 -keyout ./test.key -out ./test.csr -subj "/C=XX/ST=Confusion/L=Somewhere/O=example/CN=$(hostname)"
  # process the signing request and sign with the fake CA
  openssl x509 -req -in ./test.csr -CA ./myCA.pem -CAkey ./myCA.key -CAcreateserial -out ./test.crt -days 999 -sha384 -extfile ./test.ext
  # create a p12 keystore
  openssl pkcs12 -export -out test.p12 -name "$(hostname)" -inkey test.key -in test.crt -passout pass:test -passin pass:
  # create a jks truststore
  keytool -import -trustcacerts -noprompt -alias "$(hostname)" -ext san=dns:localhost,ip:127.0.0.1 -file ./myCA.pem -keystore ./truststore.jks -storepass changeit
  popd
fi

podman secret create --driver=file test-p12 ./certs/test.p12
podman secret create --driver=file test-crt ./certs/test.crt
podman secret create --driver=file test-key ./certs/test.key
podman secret create --driver=file trust-jks ./certs/truststore.jks
podman secret create --driver=file trust-pem ./certs/myCA.pem

podman network create services_network

podman pod create \
 --name proxy \
 --network podman,services_network \
 --publish 8443:8443

podman pod create \
 --name greeting-service \
 --network services_network

podman pod create \
 --name portainer \
 --network services_network \
 --publish 9443:9443

podman run -d \
 --name greeting_service \
 --pod greeting-service \
 --secret source=test-p12,target=/certs/test.p12,type=mount \
 --secret source=trust-jks,target=/certs/trust.jks,type=mount \
 --env "OUTER_HOST=$(hostname)" \
 docker.io/library/greeting-service

podman run -d \
 --name portainer_ce \
 --pod portainer \
 --secret source=test-p12,target=/certs/test.p12,type=mount \
 --secret source=trust-jks,target=/certs/trust.jks,type=mount \
 --volume /run/user/1000/podman/podman.sock:/var/run/docker.sock:Z \
 docker.io/portainer/portainer-ce

podman run -d \
 --name caddy \
 --pod proxy \
 --secret source=test-crt,target=/certs/test.crt,type=mount \
 --secret source=test-key,target=/certs/test.key,type=mount \
 --secret source=trust-pem,target=/certs/trust.pem,type=mount \
 --volume ./Caddyfile:/etc/caddy/Caddyfile \
 --volume ./errors:/var/www/errors \
 --env "OUTER_HOST=$(hostname)" \
 docker.io/library/caddy:2.6.2-alpine
