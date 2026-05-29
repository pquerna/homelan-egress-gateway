# Fix Unframed Tunnel Response Hangs

## Summary

Fix an HTTP/1.1 tunnel hang for unknown-length upstream responses.

When CrabTrap MITMs an HTTPS `CONNECT` tunnel, some upstream responses arrive
without `Content-Length` and without `Transfer-Encoding`. In that case, EOF is
the only valid response-body delimiter. CrabTrap was writing the response body
to the client but keeping the tunnel open, causing clients like `curl` to wait
indefinitely after receiving the full body.

This changes tunnel keep-alive behavior so unframed, unknown-length responses
close the tunnel after the response is written.

## Reproduction

This hung behind CrabTrap before the fix:

```bash
curl -fsSL \
  --proxy 'http://gat_local_ct100_dev:@192.168.32.100:8080' \
  --cacert /opt/egress-gateway/crabtrap/certs/ca.crt \
  https://api.github.com/repos/openai/codex/releases/latest \
  -o /tmp/codex-release.json
```

Verbose output showed the response body was fully received, but curl waited for
EOF:

```text
< HTTP/1.1 200 OK
* no chunk, no close, no size. Assume close to signal end
100 278k  0 278k ...
```

Concrete URL:

```text
https://api.github.com/repos/openai/codex/releases/latest
```

This was observed while running the Codex installer from:

```text
https://chatgpt.com/codex/install.sh
```

## Fix

If a tunnel response has:

- a response body
- `ContentLength < 0`
- no `TransferEncoding`
- no explicit close handling already present

then CrabTrap no longer keeps the HTTP/1.1 tunnel alive. Closing the tunnel
gives the client the EOF delimiter it is waiting for.

## Test

Added a focused test covering unknown-length, unframed tunnel responses:

```text
TestUnknownLengthUnframedResponseDoesNotKeepTunnelAlive
```

Also manually verified the Codex release metadata and release tarball download
complete through CrabTrap after the fix.
