#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OBSERVABILITY_DIR="$ROOT/infrastructure/observability"
PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-prom/prometheus:v3.14.0}"
ALERTMANAGER_IMAGE="${ALERTMANAGER_IMAGE:-prom/alertmanager:v0.34.0}"

for script in \
  "$ROOT/scripts/deploy_vm_release.sh" \
  "$ROOT/scripts/deploy_remote.sh" \
  "$ROOT/scripts/tests/deploy_vm_release_test.sh" \
  "$ROOT/scripts/tests/observability_config_test.sh"; do
  bash -n "$script"
done
sh -n "$OBSERVABILITY_DIR/alertmanager/entrypoint.sh"
sh -n "$OBSERVABILITY_DIR/alertmanager/generate-config.sh"
bash "$ROOT/scripts/tests/deploy_vm_release_test.sh"

docker compose \
  --project-name ledgerly \
  --profile observability \
  -f "$OBSERVABILITY_DIR/docker-compose.observability.yml" \
  -f "$ROOT/infrastructure/docker/docker-compose.prod.yml" \
  -f "$ROOT/infrastructure/docker/docker-compose.vm.yml" \
  --env-file "$ROOT/infrastructure/docker/env.vm.example" \
  config --quiet

docker run --rm \
  --entrypoint promtool \
  -v "$OBSERVABILITY_DIR/prometheus:/etc/prometheus:ro" \
  -w /etc/prometheus \
  "$PROMETHEUS_IMAGE" \
  check config prometheus.yml

docker run --rm \
  --entrypoint promtool \
  -v "$OBSERVABILITY_DIR/prometheus:/etc/prometheus:ro" \
  -w /etc/prometheus \
  "$PROMETHEUS_IMAGE" \
  check rules backup-alerts.yml platform-alerts.yml

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
ALERTMANAGER_WEBHOOK_URL="https://alerts.example.invalid/ledgerly?token=a&b=c" \
ALERTMANAGER_SEND_RESOLVED=true \
  sh "$OBSERVABILITY_DIR/alertmanager/generate-config.sh" \
  "$temporary_dir/alertmanager.yml"
chmod 755 "$temporary_dir"
chmod 644 "$temporary_dir/alertmanager.yml"

docker run --rm \
  --entrypoint amtool \
  -v "$temporary_dir:/config:ro" \
  "$ALERTMANAGER_IMAGE" \
  check-config /config/alertmanager.yml

python3 - "$OBSERVABILITY_DIR/grafana/dashboards/ledgerly-operations.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    dashboard = json.load(handle)

assert dashboard["uid"] == "ledgerly-operations"
assert dashboard["title"] == "Ledgerly Operations"
assert len(dashboard["panels"]) >= 8
assert all(panel.get("targets") for panel in dashboard["panels"])
print("observability configuration valid")
PY
