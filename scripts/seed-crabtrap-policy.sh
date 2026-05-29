#!/usr/bin/env bash
set -euo pipefail

EGRESS_HOME=/opt/egress-gateway
GATEWAY_USER="${GATEWAY_USER:-ct-lan-restricted}"
GATEWAY_AUTH_TOKEN="${GATEWAY_AUTH_TOKEN:-gat_local_ct100_dev}"

if [[ "${GATEWAY_AUTH_TOKEN}" != gat_* ]]; then
  echo "GATEWAY_AUTH_TOKEN must start with gat_" >&2
  exit 1
fi

echo "Waiting for egress-postgres to accept connections..."
for _ in $(seq 1 60); do
  if podman exec egress-postgres pg_isready -U crabtrap -d crabtrap >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "Waiting for CrabTrap migrations to create tables..."
for _ in $(seq 1 60); do
  if podman exec egress-postgres psql -U crabtrap -d crabtrap -tAc "SELECT to_regclass('public.users')" | grep -q users; then
    break
  fi
  sleep 1
done

podman exec \
  -i egress-postgres \
  psql \
    -U crabtrap \
    -d crabtrap \
    -v "gateway_user=${GATEWAY_USER}" \
    -v "gateway_token=${GATEWAY_AUTH_TOKEN}" \
    -f - < "${EGRESS_HOME}/crabtrap/policy.seed.sql"

echo "Seeded CrabTrap user: ${GATEWAY_USER}"
echo "Seeded gateway auth token: ${GATEWAY_AUTH_TOKEN}"
echo "Use proxy URL: http://${GATEWAY_AUTH_TOKEN}:@192.168.32.100:8080"
