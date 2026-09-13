#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../deploy_vm_release.sh
source "$SCRIPT_DIR/../deploy_vm_release.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
APP_DIR="$TEST_ROOT/app"
FIRST_RELEASE="$APP_DIR/runtime-releases/1-1"
SECOND_RELEASE="$APP_DIR/runtime-releases/2-1"

mkdir -p "$FIRST_RELEASE" "$SECOND_RELEASE"
printf 'OBSERVABILITY_ENABLED=true\n' > "$APP_DIR/.env.prod"
for release in "$FIRST_RELEASE" "$SECOND_RELEASE"; do
  touch "$release/docker-compose.prod.yml" "$release/docker-compose.vm.yml"
  mkdir -p \
    "$release/observability/prometheus" \
    "$release/observability/alertmanager" \
    "$release/observability/grafana/dashboards" \
    "$release/observability/grafana/provisioning/datasources" \
    "$release/observability/grafana/provisioning/dashboards"
  touch \
    "$release/observability/docker-compose.observability.yml" \
    "$release/observability/prometheus/prometheus.yml" \
    "$release/observability/prometheus/backup-alerts.yml" \
    "$release/observability/prometheus/platform-alerts.yml" \
    "$release/observability/alertmanager/generate-config.sh" \
    "$release/observability/alertmanager/entrypoint.sh" \
    "$release/observability/grafana/provisioning/datasources/prometheus.yml" \
    "$release/observability/grafana/provisioning/dashboards/ledgerly.yml" \
    "$release/observability/grafana/dashboards/ledgerly-operations.json"
done

docker() {
  printf '%s\n' "$*" >> "$TEST_ROOT/docker.log"
  return 0
}

runtime_has_observability "$FIRST_RELEASE"
if OBSERVABILITY_ENABLED=false observability_enabled; then
  printf 'observability_enabled ignored an explicit false override\n' >&2
  exit 1
fi

activate_runtime "$FIRST_RELEASE"
test "$(readlink "$APP_DIR/runtime-current")" = "$FIRST_RELEASE"
grep -Eq -- '--profile observability' "$TEST_ROOT/docker.log"
grep -Eq 'observability/docker-compose.observability.yml' "$TEST_ROOT/docker.log"

printf 'sentinel\n' > "$APP_DIR/.previous-runtime"
activate_runtime "$FIRST_RELEASE"
test "$(tr -d '\r\n' < "$APP_DIR/.previous-runtime")" = "sentinel"

activate_runtime "$SECOND_RELEASE"
test "$(readlink "$APP_DIR/runtime-current")" = "$SECOND_RELEASE"
test "$(tr -d '\r\n' < "$APP_DIR/.previous-runtime")" = "$FIRST_RELEASE"

compose() {
  return 1
}

if deploy_and_verify; then
  printf 'deploy_and_verify ignored a compose failure\n' >&2
  exit 1
fi

printf '%s' '{"status":"ready","intervalHours":24,"ageSeconds":60}' | \
  validate_backup_health_json
printf '%s' '{"status":"never_run","intervalHours":24,"ageSeconds":null}' | \
  validate_backup_health_json
printf '%s' '{"status":"ready","intervalHours":24,"lastRecoveryDrill":{"outcome":"success"}}' | \
  validate_backup_health_json

if printf '%s' '{"status":"disabled","intervalHours":24}' | \
  validate_backup_health_json 2>/dev/null; then
  printf 'validate_backup_health_json accepted disabled backups\n' >&2
  exit 1
fi

if printf '%s' '{"status":"ready","intervalHours":24,"bundlePath":"/secret"}' | \
  validate_backup_health_json 2>/dev/null; then
  printf 'validate_backup_health_json accepted sensitive fields\n' >&2
  exit 1
fi

if printf '%s' '{"status":"ready","intervalHours":24,"lastRecoveryDrill":{"outcome":"failed","bundlePath":"/secret"}}' | \
  validate_backup_health_json 2>/dev/null; then
  printf 'validate_backup_health_json accepted sensitive recovery drill fields\n' >&2
  exit 1
fi
