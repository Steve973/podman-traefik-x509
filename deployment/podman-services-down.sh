#!/bin/bash

podman pod stop services_proxy greeting-service
podman pod rm services_proxy greeting-service
podman network rm services_network
podman secret rm test-crt test-key trust-pem
