This requires a machine where you have podman working.  This will generate certs and a truststore.
After getting podman set up, you can run these commands in order:
```
mvn clean install spring-boot:build-image
cd resources/deployment
sh ./podman-stack.sh --start all
```
Now you can access `https://localhost:8443/greeting-service/greeting?name=YourName` by using curl:
```
curl \
 --tlsv1.2 \
 --tls-max 1.2 \
 --key /tmp/certs/test.key \
 --cert /tmp/certs/test.crt \
 --insecure \
 -vvv \
 "https://localhost:8443/greeting-service/greeting?name=World"
```

The Traefik services stack dashboard is available at `https://services.localhost:8443`
The Traefik data stack dashboard is available at `https://data.localhost:8444`

You can bring all pods down, remove the network, and remove the secrets by running:
```
sh ./podman-stack.sh --stop all
```
If you want the certs to be re-generated, then remove the certs directory prior to running
```
sh ./podman-stack.sh --clean
```
