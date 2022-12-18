This requires a machine where you have podman working.  This will generate certs and a truststore.
After getting podman set up, you can run these commands in order:
```
mvn clean install spring-boot:build-image
cd src/main/resources
sh ./podman-up.sh
```
Now you can access `https://localhost:8443/greeting-service/greeting?name=YourName` by using curl:
```
curl \
 --tlsv1.2 \
 --tls-max 1.2 \
 --key ./certs/test.key \
 --cert ./certs/test.crt \
 --insecure \
 -vvv \
 "https://localhost:8443/greeting-service/greeting?name=World"
```
Portainer is available at `https://localhost:9443`

You can bring all pods down, remove the network, and remove the secrets by running:
```
sh ./podman-down.sh
```
If you want the certs to be re-generated, then remove the certs directory prior to running the
`podman-up.sh` script.