# Home LAN Time Bandit Egress and LLM Gateway

This repository deploys the gateway used by the guarded host
`192.168.32.200` and the two DGX Spark model tiers.

## Endpoints

| Service | Address | Purpose |
|---|---|---|
| Unbound | `192.168.32.100:53/tcp+udp` | Guarded DNS resolver and local `spark.home.arpa` records |
| Time Bandit explicit proxy | `192.168.32.100:8080` | Audited observe-mode HTTPS `CONNECT` egress |
| LLM API TLS frontend | `https://llm-gateway.spark.home.arpa:8181/v1` | Authenticated OpenAI/Anthropic-compatible model API |
| Time Bandit LLM listener | `127.0.0.1:8182` | Loopback-only API behind the TLS frontend |
| Time Bandit admin HTTP | `127.0.0.1:9901` | Read-only local administration |

The LLM API routes to:

- Fast: DeepSeek V4 Flash at `vllm.spark.home.arpa:8000`
- Smart: GPT-5.6 Sol through the authenticated OMP gateway at
  `omp-gateway.spark.home.arpa:4001`

The two model links use HTTP on the trusted management LAN. They still pass
through Time Bandit's resolve-then-pin SSRF guard, exact provider profiles,
credential vending, body inspection, route deadlines, and causal audit.

## LLM routes

The API requires `Authorization: Bearer <TB_LLM_CLIENT_TOKEN>` and accepts
OpenAI Chat Completions, OpenAI Responses, and Anthropic Messages requests.

| Model id | Behavior |
|---|---|
| `agent-default` | Stage router: DeepSeek classifies and serves routine work; GPT-5.6 Sol serves capability-bound work |
| `fast` | Direct DeepSeek V4 Flash passthrough |
| `smart` | Direct GPT-5.6 Sol passthrough through the OMP auth gateway |

The DeepSeek target pins `reasoning_effort: none`. This disables model thinking
for the classifier, keeping its structured verdict inside the 512-token judge
budget. The smart target pins `xhigh`.

Example:

```bash
TOKEN="$(cat ~/.config/timebandit/client.token)"

curl -sS https://llm-gateway.spark.home.arpa:8181/v1/chat/completions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "agent-default",
    "messages": [{"role": "user", "content": "What is 2 + 2?"}]
  }'
```

On a guarded client, `HTTPS_PROXY=http://192.168.32.100:8080` carries that
request through the only permitted egress socket.

## Egress policy

The explicit proxy listener runs in `observe` mode. Existing allowlist rules
still resolve known destinations as `ALLOW`; unmatched public destinations are
forwarded while the audit records their would-be `DENY`, destination host,
pinned IP, source, and enforcement as `monitor_only`.

This exception is listener-scoped. The authenticated LLM API and model-routing
policy remain globally enforced. Time Bandit's SSRF floor also remains active:
private, loopback, link-local, reserved, and cloud-metadata destinations are
still blocked.

Port `8080` is CONNECT-only. Plain HTTP absolute-form proxy requests are
rejected with `400`; guarded clients must use HTTPS origin URLs. In particular,
install `guarded-host/debian.sources` at
`/etc/apt/sources.list.d/debian.sources` before running APT.

The guarded host also enforces this socket boundary in `/etc/nftables.conf`:
The tracked source is `firewall/guarded-host.nft`.

- DNS only to `192.168.32.100:53/tcp+udp`
- TCP only to `192.168.32.100:8080`
- loopback and established connections
- all other outbound connections dropped

The in-guest nftables rule is active protection. Proxmox firewalling should
mirror the same allowlist as an outer boundary that guest root cannot change.

## Security boundary

- The LLM listener rejects unauthenticated requests.
- Observe mode applies only to the public explicit-proxy listener; LLM
  authentication, credential vending, and model-route policy remain enforced.
- `/etc/egress-gateway/timebandit.env` is root-owned mode `0600`; credentials
  are not stored in this repository.
- Time Bandit injects target credentials only after policy and route selection.
- Private model destinations require the explicit
  `dev.allow_private_destinations: true` deployment opt-in.
- Only `vllm_openai_chat_v1` and `omp_auth_gateway_responses_v1` permit
  `scheme: http`; public-provider profiles still require verified TLS/H2.
- HTTP model connections are resolve-then-pinned, non-redirecting, and
  non-pooled.
- The LLM TLS leaf is signed by the existing gateway CA. The upstream trust
  bundle contains both Debian system roots and that local CA.
- Audit records go to the system journal and contain routing metadata, not
  prompts, provider bodies, or bearer values.

## Runtime layout

```text
/opt/egress-gateway/
  timebandit/
    bin/tb
    config.llm.yaml
  llm-tls/
    server.crt
    server.key
    upstream-ca-bundle.crt
  unbound/
    Containerfile
    unbound.conf
  quadlet/
    egress-unbound.container
  systemd/
    egress-timebandit.service
    egress-llm-tls.service

/etc/egress-gateway/timebandit.env
/run/timebandit/admin.sock
```

Operational logs and structured audits:

```bash
journalctl -u egress-timebandit.service -f
```

## Prerequisites

1. Install a gateway-enabled `tb` build at
   `/opt/egress-gateway/timebandit/bin/tb`. The self-hosted profiles and guarded
   HTTP transport landed through
   [PR #291](https://github.com/ductone/timebandit-proxy/pull/291) and
   [PR #292](https://github.com/ductone/timebandit-proxy/pull/292).
2. Run the OMP auth broker on the orchestration host.
3. Run the authenticated OMP auth gateway on `192.168.32.101:4001`.
4. Create `/etc/egress-gateway/timebandit.env`:

```text
TB_LLM_CLIENT_TOKEN=<random client bearer>
VLLM_LOCAL_TOKEN=<random target bearer>
OMP_LOCAL_TOKEN=<OMP auth-gateway bearer>
```

`VLLM_LOCAL_TOKEN` is injected even though the current vLLM service does not
enforce it. This preserves a credentialed target contract without exposing a
target credential to API callers.

## Install or update

Place this checkout at `/opt/egress-gateway`, provision the binary and secret
environment file, then run:

```bash
cd /opt/egress-gateway
sudo ./scripts/install.sh
```

The installer validates the config, removes obsolete CrabTrap/Postgres
Quadlets and stale NAT, rebuilds Unbound, generates the LLM TLS leaf, and
enables:

- `egress-unbound.service`
- `egress-timebandit.service`
- `egress-llm-tls.service`

The legacy CrabTrap source and generic Time Bandit configs remain for
reference; they are not active services.

## OMP client configuration

OMP can read the gateway bearer from a root-only file:

```yaml
providers:
  timebandit:
    baseUrl: https://llm-gateway.spark.home.arpa:8181/v1
    apiKey: "!cat /root/.config/timebandit/client.token"
    authHeader: true
    api: openai-responses
    models:
      - id: agent-default
        name: Time Bandit Triage
        api: openai-responses
        reasoning: true
        supportsTools: true
        contextWindow: 272000
        maxTokens: 131072
```

Guarded OMP clients must trust the gateway CA and set
`HTTPS_PROXY=http://192.168.32.100:8080`.

## Verification

```bash
systemctl is-active \
  egress-unbound.service \
  egress-timebandit.service \
  egress-llm-tls.service

# Expected: 200, with a would-be-DENY audit record
curl -o /dev/null -w '%{http_code}\n' https://example.com
journalctl -u egress-timebandit.service --grep example.com

# Expected: 401
curl -o /dev/null -w '%{http_code}\n' \
  https://llm-gateway.spark.home.arpa:8181/v1/models

# Expected: 200
curl -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $(cat ~/.config/timebandit/client.token)" \
  https://llm-gateway.spark.home.arpa:8181/v1/models
```
