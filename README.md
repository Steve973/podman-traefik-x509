This requires a machine where you have podman working.  This will generate certs and a truststore.
After getting podman set up, you can simply `mvn clean install spring-boot:build-image`, and then
`cd src/main/resources` and execute `sh ./podman-up.sh`.
Now you can access `https://localhost:8443/greeting-service/greeting?name=YourName` by using curl:
```
curl \
 --tlsv1.2 \
 --tls-max 1.2 \
 --key ./certs/test.key \
 --cert ./certs/test.crt \
 --insecure \
 -vvv \
 "https://localhost:8443/greeting-service/greeting?name=World"`
```