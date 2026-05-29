# Proxmox LXC Egress Enforcement

This guide shows how to restrict one Proxmox LXC so its only outbound network
path is the local egress gateway:

- DNS: `192.168.32.100:53/tcp+udp`
- CrabTrap proxy: `192.168.32.100:8080/tcp`

The LXC proxy variables are convenience configuration. The Proxmox firewall is
the enforcement boundary.

## Assumptions

Replace these examples with the real container values:

```text
Gateway IP:        192.168.32.100
Gateway subnet:    192.168.32.0/20
Example CTID:      100
Example LXC IP:    192.168.32.150/20
Example gateway:   192.168.32.1
CrabTrap token:    gat_local_ct100_dev
```

The restricted LXC should have a static IP. If the container uses DHCP, do not
enable `ipfilter` until the Proxmox firewall has an IP set that matches the
assigned address.

## Proxmox Host Configuration

Make sure the Proxmox firewall is enabled at the datacenter and node level.
In the UI this is under `Datacenter -> Firewall -> Options` and
`Node -> Firewall -> Options`.

For CTID `100`, make sure the container NIC has firewalling enabled:

```ini
# /etc/pve/lxc/100.conf
net0: name=eth0,bridge=vmbr1,ip=192.168.32.150/20,gw=192.168.32.1,firewall=1
```

Then create or replace the CT firewall file:

```bash
cat >/etc/pve/firewall/100.fw <<'EOF'
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: DROP
ipfilter: 1

[RULES]
# DNS to egress gateway only
OUT ACCEPT -p udp -dest 192.168.32.100 -dport 53
OUT ACCEPT -p tcp -dest 192.168.32.100 -dport 53

# CrabTrap proxy only
OUT ACCEPT -p tcp -dest 192.168.32.100 -dport 8080
EOF
```

Do not add general outbound allow rules such as `OUT ACCEPT -p tcp -dport 443`.
That would bypass CrabTrap.

Apply/reload the firewall:

```bash
pve-firewall compile
systemctl reload pve-firewall
```

If the container is already running, restart it after changing `net0`:

```bash
pct restart 100
```

## LXC Guest DNS

Inside the restricted LXC, point DNS at Unbound on the gateway:

```bash
cat >/etc/resolv.conf <<'EOF'
nameserver 192.168.32.100
options timeout:1 attempts:2
EOF
```

If the guest uses `systemd-resolved`, configure DNS there instead of editing
`/etc/resolv.conf` directly.

## LXC Guest Global Proxy Environment

CrabTrap requires Basic proxy authentication. The gateway-auth token is used as
the proxy username with an empty password:

```bash
cat >/etc/environment <<'EOF'
HTTP_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080
HTTPS_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080
http_proxy=http://gat_local_ct100_dev:@192.168.32.100:8080
https_proxy=http://gat_local_ct100_dev:@192.168.32.100:8080
NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100
no_proxy=localhost,127.0.0.1,::1,192.168.32.100
EOF
```

`/etc/environment` is read by PAM login sessions. It is a good global default
for interactive users, but it is not enough for every daemon or package manager.
Also install a shell profile file for POSIX shells:

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

For systemd services inside the LXC, either set a manager-wide default
environment or use service-specific drop-ins. Service-specific drop-ins are
more explicit and safer when only some daemons should use the proxy.

Manager-wide systemd default:

```bash
mkdir -p /etc/systemd/system.conf.d

cat >/etc/systemd/system.conf.d/egress-proxy.conf <<'EOF'
[Manager]
DefaultEnvironment="HTTP_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080"
DefaultEnvironment="HTTPS_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080"
DefaultEnvironment="http_proxy=http://gat_local_ct100_dev:@192.168.32.100:8080"
DefaultEnvironment="https_proxy=http://gat_local_ct100_dev:@192.168.32.100:8080"
DefaultEnvironment="NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100"
DefaultEnvironment="no_proxy=localhost,127.0.0.1,::1,192.168.32.100"
EOF

systemctl daemon-reexec
```

Service-specific drop-in:

```bash
mkdir -p /etc/systemd/system/example-agent.service.d

cat >/etc/systemd/system/example-agent.service.d/proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080"
Environment="HTTPS_PROXY=http://gat_local_ct100_dev:@192.168.32.100:8080"
Environment="NO_PROXY=localhost,127.0.0.1,::1,192.168.32.100"
EOF

systemctl daemon-reload
systemctl restart example-agent.service
```

Some tools keep their own proxy configuration. Set these when relevant:

```bash
git config --system http.proxy  http://gat_local_ct100_dev:@192.168.32.100:8080
git config --system https.proxy http://gat_local_ct100_dev:@192.168.32.100:8080
```

```bash
npm config set proxy http://gat_local_ct100_dev:@192.168.32.100:8080 --global
npm config set https-proxy http://gat_local_ct100_dev:@192.168.32.100:8080 --global
```

```bash
mkdir -p /etc/pip.conf.d
cat >/etc/pip.conf <<'EOF'
[global]
proxy = http://gat_local_ct100_dev:@192.168.32.100:8080
EOF
```

## APT Proxy

Configure APT explicitly. This avoids relying on shell profile files:

```bash
cat >/etc/apt/apt.conf.d/01egress-proxy <<'EOF'
Acquire::http::Proxy "http://gat_local_ct100_dev:@192.168.32.100:8080";
Acquire::https::Proxy "http://gat_local_ct100_dev:@192.168.32.100:8080";
EOF
```

The current CrabTrap seed policy should allow normal Debian package reads after
LLM inspection:

```text
http://deb.debian.org/debian
http://security.debian.org
```

## Install CrabTrap CA In The LXC

CrabTrap intercepts HTTPS and issues certificates from its local CA. HTTPS
clients inside the LXC must trust that CA.

The CA on the gateway is:

```text
/opt/egress-gateway/crabtrap/certs/ca.crt
```

From the Proxmox host, after copying `ca.crt` there or mounting the gateway
filesystem, inject it into CTID `100`:

```bash
pct push 100 ca.crt /usr/local/share/ca-certificates/crabtrap.crt -perms 0644
pct exec 100 -- update-ca-certificates
```

Alternatively, from inside the LXC, copy the CA file into place and update the
trust store:

```bash
install -m 0644 ca.crt /usr/local/share/ca-certificates/crabtrap.crt
update-ca-certificates
```

Do not copy `ca.key` into the LXC. The private key stays on the gateway.

## Validation From Inside The LXC

These should pass:

```bash
dig +time=2 +tries=1 deb.debian.org @192.168.32.100
curl -I --connect-timeout 10 https://deb.debian.org
curl -I --connect-timeout 10 https://api.github.com
```

These should fail:

```bash
dig +time=2 +tries=1 deb.debian.org @1.1.1.1
curl -I --connect-timeout 5 --noproxy '*' https://example.com
curl -I --connect-timeout 5 --noproxy '*' http://169.254.169.254/latest/meta-data/
curl -I --connect-timeout 5 --noproxy '*' http://192.168.32.1
```

Arbitrary browsing or exfiltration-shaped requests should return `403` through
CrabTrap:

```bash
curl -I --connect-timeout 10 https://example.com
curl -I --connect-timeout 10 'https://api.github.com/?token=sk-test&path=/home/user/.ssh/id_ed25519'
```

On the gateway, confirm decisions in CrabTrap logs:

```bash
journalctl -u egress-crabtrap.service -f
```

And in the audit database:

```bash
podman exec egress-postgres psql -U crabtrap -d crabtrap \
  -c "SELECT timestamp, user_id, method, url, decision, approved_by, response_status FROM audit_log ORDER BY timestamp DESC LIMIT 20;"
```

## Troubleshooting

If all outbound traffic works directly, the Proxmox firewall is not enforcing
the CT boundary. Check `firewall=1` on the CT NIC, CT firewall `enable: 1`, and
datacenter/node firewall enablement.

If HTTPS through CrabTrap fails with a certificate error, install
`crabtrap/certs/ca.crt` into the LXC trust store and run
`update-ca-certificates`.

If CrabTrap returns `407`, the proxy URL is missing the gateway-auth token or
the token does not match the seeded CrabTrap user.

If CrabTrap returns `403`, the request reached CrabTrap and was denied by
policy. Add the destination to `crabtrap/policy.seed.sql`, rerun
`/opt/egress-gateway/scripts/seed-crabtrap-policy.sh`, then retest.
