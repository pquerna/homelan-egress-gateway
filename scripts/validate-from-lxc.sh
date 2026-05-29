#!/usr/bin/env bash
set -u

GATEWAY_IP="${GATEWAY_IP:-192.168.32.100}"
GATEWAY_AUTH_TOKEN="${GATEWAY_AUTH_TOKEN:-gat_local_ct100_dev}"
PROXY_URL="http://${GATEWAY_AUTH_TOKEN}:@${GATEWAY_IP}:8080"

failures=0

check_should_pass() {
  name="$1"
  shift

  echo "PASS-EXPECTED: ${name}"
  if "$@"; then
    echo "ok: ${name}"
  else
    echo "FAIL: ${name}"
    failures=$((failures + 1))
  fi
}

check_should_fail() {
  name="$1"
  shift

  echo "FAIL-EXPECTED: ${name}"
  if "$@"; then
    echo "FAIL: unexpectedly succeeded: ${name}"
    failures=$((failures + 1))
  else
    echo "ok: failed as expected: ${name}"
  fi
}

check_should_pass "gateway DNS" \
  dig +time=2 +tries=1 deb.debian.org @"${GATEWAY_IP}"

check_should_fail "direct public DNS blocked" \
  dig +time=2 +tries=1 deb.debian.org @1.1.1.1

check_should_fail "direct HTTPS blocked" \
  curl -I --connect-timeout 5 --noproxy '*' https://example.com

check_should_pass "proxy to Debian allowed" \
  curl -I --connect-timeout 10 --proxy "${PROXY_URL}" https://deb.debian.org

check_should_fail "proxy to unapproved HTTPS denied" \
  curl -I --connect-timeout 10 --proxy "${PROXY_URL}" https://example.com

check_should_fail "direct metadata service blocked" \
  curl -I --connect-timeout 5 --noproxy '*' http://169.254.169.254/latest/meta-data/

check_should_fail "direct private LAN blocked" \
  curl -I --connect-timeout 5 --noproxy '*' http://192.168.32.1

echo "failures=${failures}"
exit "${failures}"
