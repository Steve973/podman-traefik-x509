#!/bin/bash

podman pod stop proxy greeting-service
podman pod rm proxy greeting-service
podman network rm services_network
podman secret rm test-crt test-key trust-pem
