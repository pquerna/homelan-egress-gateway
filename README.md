# Minimal Local Time Bandit Egress Gateway

This project implements the local egress gateway described in the original
CrabTrap RFC, adjusted for this LAN and the current proxy implementation:

- Gateway LAN IP: `192.168.32.100`
- LAN subnet: `192.168.32.0/20`
- DNS service exposed to LAN: `192.168.32.100:53/tcp+udp`
- Time Bandit proxy exposed to LAN: `192.168.32.100:8080/tcp`

The security boundary is still the LXC firewall. Restricted containers must
only be able to open outbound sockets to `192.168.32.100:53` and
`192.168.32.100:8080`.

## Current Proxy Reality

The gateway now runs Time Bandit as the egress proxy instead of CrabTrap.
Unbound still provides DNS.

Time Bandit is installed as a host systemd service:

- Unit: `egress-timebandit.service`
- Runtime config: `/opt/egress-gateway/timebandit/config.yaml`
- Standard config: `/opt/egress-gateway/timebandit/config.standard.yaml`
- Temporary open config: `/opt/egress-gateway/timebandit/config.open.yaml`
- Audit log: `/opt/egress-gateway/timebandit/log/audit.jsonl`
- Admin HTTP: `127.0.0.1:9901`
- Admin socket: `/run/timebandit/admin.sock`

The service reuses the existing local CA files at:

```text
/opt/egress-gateway/crabtrap/certs/ca.crt
/opt/egress-gateway/crabtrap/certs/ca.key
```

Do not copy `ca.key` into client containers.

## Combined Proxy Listener

Time Bandit runs as a combined explicit proxy on `192.168.32.100:8080`.
Restricted clients can use the same proxy URL for both variables:

```bash
HTTP_PROXY=http://192.168.32.100:8080
HTTPS_PROXY=http://192.168.32.100:8080
```

`HTTPS_PROXY` traffic uses HTTP `CONNECT` and forged-cert MITM. `HTTP_PROXY`
traffic uses absolute-form cleartext forwarding. Both paths run through the
same destination entitlement and detection policy.

## Layout

```text
/opt/egress-gateway/
  README.md
  timebandit/
    config.standard.yaml
    config.open.yaml
    config.yaml          # runtime copy, ignored by git
    bin/                 # local Time Bandit binaries, ignored by git
    log/                 # local audit logs, ignored by git
  unbound/
    Containerfile
    unbound.conf
  quadlet/
    egress-unbound.container
  systemd/
    egress-timebandit.service
  firewall/
    nftables.conf
    proxmox-ct-example.fw
  scripts/
    build-images.sh
    install.sh
    timebandit-mode.sh
    validate-from-lxc.sh
  docs/
    rfc-ingested.md
    lxc-client-config.md
    proxmox-lxc-egress-enforcement.md
    operations.md
```

The old CrabTrap files are retained in the repo for reference and rollback, but
they are no longer the active gateway service.

## Install

Run on the Debian 13 gateway host after placing `timebanditd` and `tbctl` under
`/opt/egress-gateway/timebandit/bin/`:

```bash
cd /opt/egress-gateway
sudo ./scripts/install.sh
```

The install script installs base packages, builds the Unbound image, disables
the old CrabTrap/Postgres units if present, installs the Time Bandit systemd
unit, starts Unbound, and starts Time Bandit.

## Restricted LXC Proxy Settings

Time Bandit does not require a gateway-auth token in the proxy URL.

```bash
export HTTP_PROXY=http://192.168.32.100:8080
export HTTPS_PROXY=http://192.168.32.100:8080
export NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100
```

Install the gateway CA into each restricted LXC trust store before expecting
normal HTTPS tools to work through the proxy.

## Standard Policy

Standard mode is default-deny and allows known software and LLM service
destinations:

- Debian package repositories
- npm registry reads
- PyPI metadata and Python package files
- GitHub and GitHubusercontent
- OpenAI API, ChatGPT auth/backend endpoints used by Codex

Unapproved public destinations are denied. Private, loopback, link-local, and
metadata destinations remain blocked by Time Bandit and by the LXC firewall.

## Egress Modes

```bash
/opt/egress-gateway/scripts/timebandit-mode.sh status
/opt/egress-gateway/scripts/timebandit-mode.sh standard
/opt/egress-gateway/scripts/timebandit-mode.sh open 30m
```

Open mode allows public destinations temporarily while keeping Time Bandit
running, preserving audit logging and built-in private-network protections.

## Firewall

Use `firewall/nftables.conf` as the gateway host firewall baseline. It allows:

- DNS from `192.168.32.0/20`
- Time Bandit proxy from `192.168.32.0/20`
- SSH from `192.168.32.0/20`

The Proxmox LXC firewall must still enforce the restricted-container outbound
boundary. See `docs/proxmox-lxc-egress-enforcement.md`.
