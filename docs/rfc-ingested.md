# RFC Ingest Notes

Original RFC target:

- Debian 13 gateway.
- Podman Quadlet services.
- Unbound DNS resolver.
- CrabTrap HTTP/HTTPS egress proxy.
- Gateway exposed only on DNS and proxy ports.
- Proxmox firewall as the hard security boundary.

Local network substitutions:

- `10.10.20.10` became `192.168.32.100`.
- `10.10.20.0/24` became `192.168.32.0/20`.
- Incoming LXC/client traffic is allowed from anywhere on the LAN.
- SSH to the gateway is allowed from anywhere on the LAN.

Upstream CrabTrap substitutions:

- The RFC's `policy.yaml` does not match current upstream CrabTrap.
- Static rules are seeded into PostgreSQL through `crabtrap/policy.seed.sql`.
- CrabTrap requires a gateway-auth token in the proxy URL.
- CrabTrap requires its CA to be trusted by clients for HTTPS interception.
- PostgreSQL is required as a local support service, but it is not exposed on
  the LAN.

Deferred work remains deferred:

- No Smokescreen.
- No Envoy.
- No package cache.
- No Debian mirror.
- No Kubernetes.
- No Docker Compose.
