#!/bin/bash

podman pod stop proxy portainer greeting-service
podman pod rm proxy portainer greeting-service
podman network rm services_network
podman secret rm test-p12 test-crt test-key trust-jks trust-pem
