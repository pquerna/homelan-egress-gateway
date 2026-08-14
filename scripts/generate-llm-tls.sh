#!/usr/bin/env bash
set -euo pipefail

EGRESS_HOME=/opt/egress-gateway
CA_DIR="$EGRESS_HOME/crabtrap/certs"
TLS_DIR="$EGRESS_HOME/llm-tls"
CERT="$TLS_DIR/server.crt"
KEY="$TLS_DIR/server.key"

if [[ ! -s "$CA_DIR/ca.crt" || ! -s "$CA_DIR/ca.key" ]]; then
  echo "missing gateway CA under $CA_DIR" >&2
  exit 1
fi

install -d -m 0750 "$TLS_DIR"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cat /etc/ssl/certs/ca-certificates.crt "$CA_DIR/ca.crt" \
  >"$workdir/upstream-ca-bundle.crt"
install -m 0644 "$workdir/upstream-ca-bundle.crt" \
  "$TLS_DIR/upstream-ca-bundle.crt"

if [[ -s "$CERT" && -s "$KEY" ]] && openssl x509 -checkend 2592000 -noout -in "$CERT"; then
  exit 0
fi

openssl req -new -newkey rsa:3072 -nodes \
  -keyout "$workdir/server.key" \
  -out "$workdir/server.csr" \
  -subj '/CN=llm-gateway.spark.home.arpa' \
  -addext 'subjectAltName=DNS:llm-gateway.spark.home.arpa,IP:192.168.32.100'

cat >"$workdir/server.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:llm-gateway.spark.home.arpa,IP:192.168.32.100
EOF

openssl x509 -req \
  -in "$workdir/server.csr" \
  -CA "$CA_DIR/ca.crt" \
  -CAkey "$CA_DIR/ca.key" \
  -set_serial "0x$(openssl rand -hex 16)" \
  -days 825 \
  -sha256 \
  -extfile "$workdir/server.ext" \
  -out "$workdir/server.crt"

install -m 0644 "$workdir/server.crt" "$CERT"
install -m 0600 "$workdir/server.key" "$KEY"
