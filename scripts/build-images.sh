#!/usr/bin/env bash
set -euo pipefail

cd /opt/egress-gateway

podman build --network=host -t localhost/egress-unbound:local ./unbound
