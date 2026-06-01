# Restricted LXC Client Configuration

The Proxmox firewall is the security boundary. The LXC should only be able to
egress to:

- `192.168.32.100:53/tcp+udp`
- `192.168.32.100:8080/tcp`

The proxy environment variables are convenience settings, not the boundary.

## Proxy Environment

Time Bandit does not require proxy Basic auth.

```bash
cat >/etc/profile.d/egress-proxy.sh <<'EOF'
export HTTP_PROXY=http://192.168.32.100:8080
export HTTPS_PROXY=http://192.168.32.100:8080
export http_proxy=http://192.168.32.100:8080
export https_proxy=http://192.168.32.100:8080

export NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100
export no_proxy=localhost,127.0.0.1,::1,192.168.32.100
EOF
```

For systemd services inside the LXC, create service-specific drop-ins because
`/etc/profile.d` does not affect systemd daemons.

## Codex CLI

Codex can load proxy settings from `~/.codex/.env`. Create this for each user
that runs Codex:

```bash
mkdir -p ~/.codex
cat >~/.codex/.env <<'EOF'
HTTP_PROXY=http://192.168.32.100:8080
HTTPS_PROXY=http://192.168.32.100:8080
http_proxy=http://192.168.32.100:8080
https_proxy=http://192.168.32.100:8080
NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100
no_proxy=localhost,127.0.0.1,::1,192.168.32.100

SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/timebandit-egress.crt
GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
EOF
chmod 0600 ~/.codex/.env
```

Do not set `all_proxy` unless you are intentionally using a SOCKS proxy. This
gateway exposes an HTTP proxy only.

## APT Proxy

Time Bandit accepts both HTTP absolute-form requests and HTTPS `CONNECT` on the
same listener. Configure both APT proxy paths:

```bash
cat >/etc/apt/apt.conf.d/01egress-proxy <<'EOF'
Acquire::http::Proxy "http://192.168.32.100:8080";
Acquire::https::Proxy "http://192.168.32.100:8080";
EOF
```

HTTP and HTTPS Debian sources are both supported through the proxy.

## DNS

```bash
cat >/etc/resolv.conf <<'EOF'
nameserver 192.168.32.100
options timeout:1 attempts:2
EOF
```

If the LXC uses `systemd-resolved`, configure the resolver there instead of
directly editing `/etc/resolv.conf`.

## Time Bandit CA

Time Bandit intercepts HTTPS and issues certificates from the gateway local CA.
Copy the gateway CA into the LXC trust store:

```bash
install -m 0644 ca.crt /usr/local/share/ca-certificates/timebandit-egress.crt
update-ca-certificates
```

The gateway-side CA path is:

```text
/opt/egress-gateway/crabtrap/certs/ca.crt
```

The path still contains `crabtrap` because the CA was originally generated
during the CrabTrap deployment and is intentionally reused to avoid rotating
client trust.

## Validation

Run from inside the restricted LXC:

```bash
/opt/egress-gateway/scripts/validate-from-lxc.sh
```
