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
  git \
  socat

install -d /etc/containers/systemd
install -d /etc/containers/systemd/disabled
install -d -m 0700 /etc/egress-gateway
install -d "$EGRESS_HOME/timebandit/bin"

install -m 0644 "$EGRESS_HOME/quadlet/egress-unbound.container" \
  /etc/containers/systemd/egress-unbound.container

for old_unit in egress-crabtrap.container egress-postgres.container egress-gateway.network; do
  if [[ -e "/etc/containers/systemd/${old_unit}" ]]; then
    mv "/etc/containers/systemd/${old_unit}" "/etc/containers/systemd/disabled/${old_unit}"
  fi
done

install -m 0644 "$EGRESS_HOME/systemd/egress-timebandit.service" \
  /etc/systemd/system/egress-timebandit.service
install -m 0644 "$EGRESS_HOME/systemd/egress-llm-tls.service" \
  /etc/systemd/system/egress-llm-tls.service

if [[ ! -x "$EGRESS_HOME/timebandit/bin/tb" ]]; then
  echo "missing $EGRESS_HOME/timebandit/bin/tb; install a gateway-enabled Time Bandit build first" >&2
  exit 1
fi
if [[ ! -s /etc/egress-gateway/timebandit.env ]]; then
  echo "missing /etc/egress-gateway/timebandit.env; provision the three bearer-token variables first" >&2
  exit 1
fi
chmod 0600 /etc/egress-gateway/timebandit.env
"$EGRESS_HOME/timebandit/bin/tb" validate "$EGRESS_HOME/timebandit/config.llm.yaml"
"$EGRESS_HOME/scripts/generate-llm-tls.sh"

systemctl stop egress-crabtrap.service egress-postgres.service egress-unbound.service \
  2>/dev/null || true
podman network rm systemd-egress-gateway 2>/dev/null || true
nft delete table inet netavark 2>/dev/null || true

"$EGRESS_HOME/scripts/build-images.sh"

systemctl daemon-reload
systemctl enable egress-unbound.service egress-timebandit.service egress-llm-tls.service
systemctl restart egress-unbound.service
systemctl restart egress-timebandit.service
systemctl restart egress-llm-tls.service

systemctl --no-pager --full status egress-unbound.service
systemctl --no-pager --full status egress-timebandit.service
systemctl --no-pager --full status egress-llm-tls.service
