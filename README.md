# Minimal Local CrabTrap Egress Gateway

This project implements the local egress gateway described in the RFC, adjusted
for this LAN:

- Gateway LAN IP: `192.168.32.100`
- LAN subnet: `192.168.32.0/20`
- DNS service exposed to LAN: `192.168.32.100:53/tcp+udp`
- CrabTrap proxy exposed to LAN: `192.168.32.100:8080/tcp`

The intended security boundary is still the LXC firewall: restricted containers
must only be able to open outbound sockets to `192.168.32.100:53` and
`192.168.32.100:8080`.

## Current CrabTrap Reality

The draft RFC assumed CrabTrap could run as a simple standalone proxy with a
YAML policy file. Current upstream CrabTrap works differently:

- It requires PostgreSQL for users, policies, and audit state.
- It requires proxy authentication with a `gat_...` gateway-auth token.
- It performs HTTPS interception using a generated CA certificate.
- Static allow/deny rules are stored in the CrabTrap database as policy records.
- The admin/API listener is hard-coded on container port `8081`.

This build keeps the external LAN exposure minimal:

- Unbound publishes only `192.168.32.100:53`.
- CrabTrap publishes only `192.168.32.100:8080`.
- CrabTrap admin/API publishes only `127.0.0.1:8081` for SSH tunneling.
- PostgreSQL is only on the private Podman network.

## Layout

```text
/opt/egress-gateway/
  README.md
  crabtrap/
    Containerfile
    config.yaml
    policy.seed.sql
    certs/
  unbound/
    Containerfile
    unbound.conf
  quadlet/
    egress-gateway.network
    egress-postgres.container
    egress-unbound.container
    egress-crabtrap.container
  firewall/
    nftables.conf
    proxmox-ct-example.fw
  scripts/
    build-images.sh
    install.sh
    seed-crabtrap-policy.sh
    validate-from-lxc.sh
  docs/
    rfc-ingested.md
    lxc-client-config.md
    operations.md
```

## Install

Run on the Debian 13 gateway host:

```bash
cd /opt/egress-gateway
sudo ./scripts/install.sh
```

The install script installs packages, builds local images, installs Quadlet
units, starts Postgres, starts Unbound, starts CrabTrap, and seeds the initial
CrabTrap static policy.

## Restricted LXC Proxy Settings

CrabTrap requires gateway-auth in the proxy URL. The default seeded token is:

```text
gat_local_ct100_dev
```

Use:

```bash
export HTTP_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080
export HTTPS_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080
export NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100
```

For HTTPS requests, CrabTrap generates a local CA at:

```text
/opt/egress-gateway/crabtrap/certs/ca.crt
```

Install that CA into each restricted LXC trust store before expecting normal
HTTPS tools to work through the proxy.

## Seeded Policy

The seed script creates one user and one published static policy. Static rules
allow only the RFC v1 destinations:

- `deb.debian.org`
- `security.debian.org`
- `github.com`
- `api.github.com`
- `registry.npmjs.org`
- `pypi.org`
- `files.pythonhosted.org`

Unmatched requests fall through to CrabTrap LLM mode with fallback `deny`.
Because the seeded policy prompt is intentionally empty, unmatched requests are
denied without needing a live LLM provider.

## Firewall

Use `firewall/nftables.conf` as the gateway host firewall baseline. It allows:

- DNS from `192.168.32.0/20`
- CrabTrap proxy from `192.168.32.0/20`
- SSH from `192.168.32.0/20`

The Proxmox LXC firewall must still enforce the restricted-container outbound
boundary. See `docs/lxc-client-config.md`.
