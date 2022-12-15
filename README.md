This requires a machine where you have podman working.  This will generate certs and a truststore.
After getting podman set up, you can simply `mvn clean install spring-boot:build-image`, and then
`cd src/main/resources` and execute `sh ./podman-up.sh`.
Now you can access `https://localhost:8443/greeting-service/greeting?name=YourName` and be sure to
tail caddy's log by issuing `podman logs -f caddy` where you will see the `tls: bad certificate`
error.
