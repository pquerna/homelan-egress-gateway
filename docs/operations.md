# Operations

## Service Status

```bash
systemctl status egress-unbound.service
systemctl status egress-timebandit.service
```

## Logs

```bash
journalctl -u egress-unbound.service -f
journalctl -u egress-timebandit.service -f
tail -f /opt/egress-gateway/timebandit/log/audit.jsonl
```

Time Bandit writes structured audit events to
`/opt/egress-gateway/timebandit/log/audit.jsonl`.

## Admin Endpoint

Time Bandit admin HTTP is bound only on gateway loopback:

```text
127.0.0.1:9901
```

Access it from a workstation with an SSH tunnel:

```bash
ssh -L 9901:127.0.0.1:9901 root@192.168.32.100
```

Then open:

```text
http://localhost:9901/
```

The admin socket is:

```text
/run/timebandit/admin.sock
```

## Rebuild Unbound

```bash
cd /opt/egress-gateway
./scripts/build-images.sh
systemctl restart egress-unbound.service
```

Time Bandit is built from `/root/timebandit-proxy` and installed as local
binaries under `/opt/egress-gateway/timebandit/bin/`.

## Egress Modes

Standard mode is the normal default. It restores the destination allowlist and
Time Bandit enforcement:

```bash
/opt/egress-gateway/scripts/timebandit-mode.sh standard
```

Open mode allows public destinations temporarily while keeping Time Bandit,
private-network defenses, and audit logging active:

```bash
/opt/egress-gateway/scripts/timebandit-mode.sh open 30m
```

The optional duration is passed to `systemd-run --on-active`; examples include
`10m`, `30m`, and `2h`. After the timer expires, the gateway resets to standard
mode. To opt out of auto-reset:

```bash
/opt/egress-gateway/scripts/timebandit-mode.sh open none
```

Check the current mode:

```bash
/opt/egress-gateway/scripts/timebandit-mode.sh status
```

## Inspect Units

```bash
systemctl cat egress-timebandit.service
systemctl cat egress-unbound.service
```

## Inspect Unbound Container

```bash
podman ps
podman logs egress-unbound
podman inspect egress-unbound
```

## Apply Gateway Firewall

Review `firewall/nftables.conf`, then:

```bash
nft -c -f /opt/egress-gateway/firewall/nftables.conf
install -m 0644 /opt/egress-gateway/firewall/nftables.conf /etc/nftables.conf
systemctl enable --now nftables
systemctl restart nftables
```

## Proxy Listener

Time Bandit runs a combined single-port explicit proxy on
`192.168.32.100:8080`.

- `HTTPS_PROXY` clients use HTTP `CONNECT` and forged-cert MITM.
- `HTTP_PROXY` clients use absolute-form cleartext forwarding.
- Both paths run through the same entitlement, SSRF floor, detection, and audit
  pipeline.
