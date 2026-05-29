# Restricted LXC Client Configuration

The Proxmox firewall is the security boundary. The LXC should only be able to
egress to:

- `192.168.32.100:53/tcp+udp`
- `192.168.32.100:8080/tcp`

The proxy environment variables are convenience settings, not the boundary.

## Proxy Environment

CrabTrap requires Basic proxy auth where the username is the gateway-auth token.
The seeded default token is `gat_local_ct100_dev`.

```bash
cat >/etc/profile.d/egress-proxy.sh <<'EOF'
export HTTP_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080
export HTTPS_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080
export http_proxy=http://gat_local_ct100_dev:@192.168.32.100:8080
export https_proxy=http://gat_local_ct100_dev:@192.168.32.100:8080

export NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100
export no_proxy=localhost,127.0.0.1,::1,192.168.32.100
EOF
```

For systemd services inside the LXC, create service-specific drop-ins because
`/etc/profile.d` does not affect systemd daemons.

## APT Proxy

```bash
cat >/etc/apt/apt.conf.d/01egress-proxy <<'EOF'
Acquire::http::Proxy "http://gat_local_ct100_dev:@192.168.32.100:8080";
Acquire::https::Proxy "http://gat_local_ct100_dev:@192.168.32.100:8080";
EOF
```

## DNS

```bash
cat >/etc/resolv.conf <<'EOF'
nameserver 192.168.32.100
options timeout:1 attempts:2
EOF
```

If the LXC uses `systemd-resolved`, configure the resolver there instead of
directly editing `/etc/resolv.conf`.

## CrabTrap CA

CrabTrap terminates HTTPS and generates certificates from its local CA. Copy the
gateway CA into the LXC trust store after the CrabTrap service has started:

```bash
install -m 0644 ca.crt /usr/local/share/ca-certificates/crabtrap.crt
update-ca-certificates
```

The gateway-side CA path is:

```text
/opt/egress-gateway/crabtrap/certs/ca.crt
```

## Validation

Run from inside the restricted LXC:

```bash
/opt/egress-gateway/scripts/validate-from-lxc.sh
```
