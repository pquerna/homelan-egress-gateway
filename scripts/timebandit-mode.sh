#!/usr/bin/env bash
set -euo pipefail

EGRESS_HOME=/opt/egress-gateway
MODE_FILE=/etc/egress-gateway/timebandit-mode
UNIT=egress-timebandit.service

usage() {
  cat <<'USAGE'
Usage:
  timebandit-mode.sh status
  timebandit-mode.sh standard
  timebandit-mode.sh open [duration]

Modes:
  standard  Enforce the configured host allowlist plus deterministic inspection.
  open      Allow all public destinations through Time Bandit while keeping
            deterministic inspection, SSRF defenses, and audit logging.

Examples:
  /opt/egress-gateway/scripts/timebandit-mode.sh open 30m
  /opt/egress-gateway/scripts/timebandit-mode.sh open 2h
  /opt/egress-gateway/scripts/timebandit-mode.sh standard
USAGE
}

install_config() {
  local mode="$1"
  local source="$2"

  install -d -m 0755 /etc/egress-gateway
  install -m 0644 "$source" "$EGRESS_HOME/timebandit/config.yaml"
  printf '%s\n' "$mode" >"$MODE_FILE"
  systemctl restart "$UNIT"
}

status_mode() {
  local mode="unknown"
  [[ -f "$MODE_FILE" ]] && mode="$(cat "$MODE_FILE")"
  echo "mode=${mode}"
  systemctl is-active "$UNIT" || true
  systemctl list-timers 'egress-timebandit-reset-open*' --no-pager || true
}

mode="${1:-}"
case "$mode" in
  status)
    status_mode
    ;;
  standard)
    systemctl cancel 'egress-timebandit-reset-open*' 2>/dev/null || true
    install_config standard "$EGRESS_HOME/timebandit/config.standard.yaml"
    status_mode
    ;;
  open)
    duration="${2:-30m}"
    install_config open "$EGRESS_HOME/timebandit/config.open.yaml"
    if [[ "$duration" != "none" ]]; then
      systemd-run \
        --unit="egress-timebandit-reset-open" \
        --on-active="$duration" \
        "$EGRESS_HOME/scripts/timebandit-mode.sh" standard >/dev/null
      echo "open mode enabled; automatic reset scheduled in ${duration}"
    else
      echo "open mode enabled with no automatic reset"
    fi
    status_mode
    ;;
  *)
    usage
    exit 2
    ;;
esac
