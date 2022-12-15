#!/bin/bash

mkdir ./certs
pushd ./certs

rm test.ext
cat > test.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName=@alt_names

[alt_names]
DNS.1=test
DNS.2=localhost
EOF

# generate the local CA key
openssl genrsa -out ./myCA.key 2048
# generate the local CA cert
openssl req -x509 -new -nodes -key ./myCA.key -sha384 -days 999 -out ./myCA.pem -subj "/C=XX/ST=Confusion/L=Somewhere/O=example/CN=CertificateAuthority"
openssl req -newkey rsa:4096 -nodes -sha384 -keyout ./test.key -out ./test.csr -subj "/C=XX/ST=Confusion/L=Somewhere/O=example/CN=$(hostname)"
openssl x509 -req -in ./test.csr -CA ./myCA.pem -CAkey ./myCA.key -CAcreateserial -out ./test.crt -days 999 -sha384 -extfile ./test.ext
openssl x509 -signkey ./test.key -in ./test.csr -req -days 999 -out ./test.crt
openssl pkcs12 -export -out test.p12 -name "localhost" -inkey test.key -in test.crt -passout pass:test -passin pass:
#openssl pkcs12 -export -nokeys -in myCA.pem -out myCA.p12 -passout pass:test -passin pass:
keytool -import -trustcacerts -noprompt -alias ca -ext san=dns:localhost,ip:127.0.0.1 -file ./myCA.pem -keystore ./truststore.jks -storepass changeit
popd

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

podman run -d \
 --name greeting_service \
 --pod greeting-service \
 --secret source=test-p12,target=/certs/test.p12,type=mount \
 --secret source=trust-jks,target=/certs/trust.jks,type=mount \
 docker.io/library/greeting-service

podman run -d \
 --name caddy \
 --pod proxy \
 --secret source=test-crt,target=/certs/test.crt,type=mount \
 --secret source=test-key,target=/certs/test.key,type=mount \
 --secret source=trust-pem,target=/certs/trust.pem,type=mount \
 --volume ./Caddyfile:/etc/caddy/Caddyfile \
 docker.io/library/caddy:2.6.2-alpine
