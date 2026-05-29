# Operations

## Service Status

```bash
systemctl status egress-postgres.service
systemctl status egress-unbound.service
systemctl status egress-crabtrap.service
```

## Logs

```bash
journalctl -u egress-unbound.service -f
journalctl -u egress-crabtrap.service -f
journalctl -u egress-postgres.service -f
```

CrabTrap audit and allow/deny decisions are emitted as JSON logs to stderr and
captured by journald.

## Rebuild

```bash
cd /opt/egress-gateway
./scripts/build-images.sh
systemctl restart egress-crabtrap.service
systemctl restart egress-unbound.service
```

## Reseed Policy

```bash
cd /opt/egress-gateway
GATEWAY_AUTH_TOKEN=gat_local_ct100_dev ./scripts/seed-crabtrap-policy.sh
```

## Inspect Generated Units

```bash
systemctl cat egress-crabtrap.service
systemctl cat egress-unbound.service
systemctl cat egress-postgres.service
```

## Inspect Containers

```bash
podman ps
podman logs egress-crabtrap
podman logs egress-unbound
podman logs egress-postgres
podman inspect egress-crabtrap
```

## Apply Gateway Firewall

Review `firewall/nftables.conf`, then:

```bash
nft -c -f /opt/egress-gateway/firewall/nftables.conf
install -m 0644 /opt/egress-gateway/firewall/nftables.conf /etc/nftables.conf
systemctl enable --now nftables
systemctl restart nftables
```
