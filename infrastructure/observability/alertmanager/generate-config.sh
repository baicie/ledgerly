#!/bin/sh
set -eu

output_path="${1:?usage: generate-config.sh OUTPUT_PATH}"
webhook_url="${ALERTMANAGER_WEBHOOK_URL:-}"
send_resolved="${ALERTMANAGER_SEND_RESOLVED:-true}"

if ! printf '%s' "$webhook_url" | grep -Eq '^https?://[^[:space:]"\\]+$'; then
  echo "ALERTMANAGER_WEBHOOK_URL must be an HTTP(S) URL without whitespace, quotes, or backslashes" >&2
  exit 1
fi

case "$send_resolved" in
  true|false) ;;
  *)
    echo "ALERTMANAGER_SEND_RESOLVED must be true or false" >&2
    exit 1
    ;;
esac

cat > "$output_path" <<EOF
global:
  resolve_timeout: 5m

route:
  receiver: ledgerly-webhook
  group_by: [alertname, job, location]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers:
        - severity="critical"
      receiver: ledgerly-webhook
      continue: false

receivers:
  - name: ledgerly-webhook
    webhook_configs:
      - url: "${webhook_url}"
        send_resolved: ${send_resolved}

inhibit_rules:
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: [alertname, job, location]
EOF
