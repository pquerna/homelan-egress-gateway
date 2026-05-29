#!/usr/bin/env bash
set -euo pipefail

EGRESS_HOME="${EGRESS_HOME:-/opt/egress-gateway}"
RUNTIME_CONFIG=/etc/egress-gateway/crabtrap-config.yaml
MODE_FILE=/etc/egress-gateway/mode
RESET_UNIT=egress-gateway-reset-standard

usage() {
  cat <<'EOF'
Usage:
  egress-mode.sh status
  egress-mode.sh standard
  egress-mode.sh open [duration]

Modes:
  standard  LLM-first policy enforcement. This is the normal/default mode.
  open      CrabTrap passthrough mode. Requests are audited but not blocked by
            policy. Use only temporarily while installing software.

Examples:
  /opt/egress-gateway/scripts/egress-mode.sh open 30m
  /opt/egress-gateway/scripts/egress-mode.sh open 2h
  /opt/egress-gateway/scripts/egress-mode.sh standard
EOF
}

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    echo "must run as root" >&2
    exit 1
  fi
}

approval_mode() {
  awk '
    /^approval:/ { in_approval=1; next }
    /^[^[:space:]]/ { in_approval=0 }
    in_approval && /^[[:space:]]+mode:/ { print $2; exit }
  ' "$RUNTIME_CONFIG" 2>/dev/null || true
}

cancel_reset_timer() {
  systemctl stop "${RESET_UNIT}.timer" "${RESET_UNIT}.service" >/dev/null 2>&1 || true
  systemctl reset-failed "${RESET_UNIT}.timer" "${RESET_UNIT}.service" >/dev/null 2>&1 || true
}

apply_config() {
  local mode="$1"
  local source="$2"

  install -d -m 0700 /etc/egress-gateway
  install -m 0644 "$source" "$RUNTIME_CONFIG"
  printf '%s\n' "$mode" >"$MODE_FILE"

  install -m 0644 "$EGRESS_HOME/quadlet/egress-crabtrap.container" \
    /etc/containers/systemd/egress-crabtrap.container

  systemctl daemon-reload
  systemctl restart egress-crabtrap.service
}

status_mode() {
  local mode="unknown"
  [[ -f "$MODE_FILE" ]] && mode="$(cat "$MODE_FILE")"
  echo "mode=${mode}"
  echo "approval.mode=$(approval_mode)"
  systemctl list-timers "${RESET_UNIT}.timer" --no-pager 2>/dev/null || true
}

mode="${1:-}"
case "$mode" in
  status)
    status_mode
    ;;

  standard)
    require_root
    cancel_reset_timer
    apply_config standard "$EGRESS_HOME/crabtrap/config.yaml"
    status_mode
    ;;

  open)
    require_root
    duration="${2:-30m}"
    apply_config open "$EGRESS_HOME/crabtrap/config.open.yaml"

    if [[ "$duration" != "none" ]]; then
      systemd-run \
        --unit="$RESET_UNIT" \
        --on-active="$duration" \
        "$EGRESS_HOME/scripts/egress-mode.sh" standard >/dev/null
      echo "open mode enabled; automatic reset scheduled in ${duration}"
    else
      echo "open mode enabled with no automatic reset"
    fi

    status_mode
    ;;

  *)
    usage >&2
    exit 2
    ;;
esac
