#!/usr/bin/env bash
set -euo pipefail

EGRESS_HOME=/opt/egress-gateway

apt-get update

apt-get install -y \
  podman \
  nftables \
  curl \
  jq \
  ca-certificates \
  dnsutils \
  git

install -d /etc/containers/systemd
install -d -m 0700 /etc/egress-gateway
install -d "$EGRESS_HOME/crabtrap/certs"

if [[ -f /root/.env-openai-key ]]; then
  install -m 0600 /root/.env-openai-key /etc/egress-gateway/crabtrap.env
else
  echo "missing /root/.env-openai-key; create /etc/egress-gateway/crabtrap.env with OPENAI_API_KEY before starting CrabTrap" >&2
fi

install -m 0644 "$EGRESS_HOME/quadlet/egress-gateway.network" \
  /etc/containers/systemd/egress-gateway.network

install -m 0644 "$EGRESS_HOME/quadlet/egress-postgres.container" \
  /etc/containers/systemd/egress-postgres.container

install -m 0644 "$EGRESS_HOME/quadlet/egress-unbound.container" \
  /etc/containers/systemd/egress-unbound.container

install -m 0644 "$EGRESS_HOME/quadlet/egress-crabtrap.container" \
  /etc/containers/systemd/egress-crabtrap.container

"$EGRESS_HOME/scripts/build-images.sh"

systemctl daemon-reload

systemctl start egress-postgres.service
systemctl start egress-unbound.service
systemctl start egress-crabtrap.service

"$EGRESS_HOME/scripts/seed-crabtrap-policy.sh"

systemctl --no-pager --full status egress-postgres.service
systemctl --no-pager --full status egress-unbound.service
systemctl --no-pager --full status egress-crabtrap.service
