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
install -d /etc/containers/systemd/disabled
install -d -m 0700 /etc/egress-gateway
install -d "$EGRESS_HOME/timebandit/log"

install -m 0644 "$EGRESS_HOME/quadlet/egress-unbound.container" \
  /etc/containers/systemd/egress-unbound.container

for old_unit in egress-crabtrap.container egress-postgres.container egress-gateway.network; do
  if [[ -e "/etc/containers/systemd/${old_unit}" ]]; then
    mv "/etc/containers/systemd/${old_unit}" "/etc/containers/systemd/disabled/${old_unit}"
  fi
done

install -m 0644 "$EGRESS_HOME/systemd/egress-timebandit.service" \
  /etc/systemd/system/egress-timebandit.service

install -m 0644 "$EGRESS_HOME/timebandit/config.standard.yaml" \
  "$EGRESS_HOME/timebandit/config.yaml"

if [[ -x "$EGRESS_HOME/timebandit/bin/tbctl" ]]; then
  "$EGRESS_HOME/timebandit/bin/tbctl" validate "$EGRESS_HOME/timebandit/config.yaml"
else
  echo "missing $EGRESS_HOME/timebandit/bin/tbctl; install Time Bandit binaries before running install.sh" >&2
  exit 1
fi

"$EGRESS_HOME/scripts/build-images.sh"

systemctl disable --now egress-crabtrap.service egress-postgres.service 2>/dev/null || true
systemctl daemon-reload

systemctl enable --now egress-unbound.service
systemctl enable --now egress-timebandit.service

printf 'standard\n' >/etc/egress-gateway/timebandit-mode

systemctl --no-pager --full status egress-unbound.service
systemctl --no-pager --full status egress-timebandit.service
