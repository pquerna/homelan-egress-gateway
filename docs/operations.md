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

## Admin UI

The CrabTrap admin UI is bound only on gateway loopback:

```text
127.0.0.1:8081
```

Access it from a workstation with an SSH tunnel:

```bash
ssh -L 8081:127.0.0.1:8081 root@192.168.32.100
```

Then open:

```text
http://localhost:8081/
```

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

## Egress Modes

Standard mode is the normal default. It restores the home egress policy:
package-manager fetches are statically allowed, and other proxied requests go
through the LLM judge.

```bash
/opt/egress-gateway/scripts/egress-mode.sh standard
```

Open mode switches CrabTrap to passthrough approval. Traffic is still audited,
but policy does not block requests. Use it only temporarily for software
installation or troubleshooting:

```bash
/opt/egress-gateway/scripts/egress-mode.sh open 30m
```

The optional duration is passed to `systemd-run --on-active`; examples include
`10m`, `30m`, and `2h`. After the timer expires, the gateway resets to standard
mode. To opt out of auto-reset:

```bash
/opt/egress-gateway/scripts/egress-mode.sh open none
```

Check the current mode:

```bash
/opt/egress-gateway/scripts/egress-mode.sh status
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
