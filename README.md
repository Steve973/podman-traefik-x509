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
 --key /tmp/certs/test.key \
 --cert /tmp/certs/test.crt \
 --insecure \
 "https://localhost:8443/greeting-service/greeting?name=World"
```

If you want to access the services dashboard or the data dashboard, you need to import the generated PKCS12 certificate:
`/tmp/certs/test.p12` into your browser.

The Traefik services stack dashboard is available at `https://services.localhost:8443`

The Traefik data stack dashboard is available at `https://data.localhost:8444`

You can bring all pods down, remove all containers, and remove the network:
```
sh ./podman-stack.sh --stop all
```
If you want the certs to be re-generated, then remove the certs directory prior to bringing up either stack:
```
sh ./podman-stack.sh --clean
```
Note that this will remove the data directories for the data apps, and they will be reinitialized after the certs are
generated when you start the stack.