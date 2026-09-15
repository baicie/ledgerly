#!/usr/bin/env bash
set -euo pipefail

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

runtime_is_valid() {
  local runtime_dir="$1"
  [[ "$runtime_dir" == "$APP_DIR/runtime-releases/"* ]] &&
    [[ -f "$runtime_dir/docker-compose.prod.yml" ]] &&
    [[ -f "$runtime_dir/docker-compose.vm.yml" ]]
}

runtime_has_observability() {
  local runtime_dir="$1"
  [[ -f "$runtime_dir/observability/docker-compose.observability.yml" ]] &&
    [[ -f "$runtime_dir/observability/prometheus/prometheus.yml" ]] &&
    [[ -f "$runtime_dir/observability/prometheus/backup-alerts.yml" ]] &&
    [[ -f "$runtime_dir/observability/prometheus/host-alerts.yml" ]] &&
    [[ -f "$runtime_dir/observability/prometheus/platform-alerts.yml" ]] &&
    [[ -f "$runtime_dir/observability/alertmanager/generate-config.sh" ]] &&
    [[ -f "$runtime_dir/observability/alertmanager/entrypoint.sh" ]] &&
    [[ -f "$runtime_dir/observability/grafana/provisioning/datasources/prometheus.yml" ]] &&
    [[ -f "$runtime_dir/observability/grafana/provisioning/dashboards/ledgerly.yml" ]] &&
    [[ -f "$runtime_dir/observability/grafana/dashboards/ledgerly-operations.json" ]] &&
    [[ -f "$runtime_dir/observability/grafana/dashboards/ledgerly-host-resources.json" ]]
}

observability_enabled() {
  case "${OBSERVABILITY_ENABLED:-}" in
    true|1) return 0 ;;
    false|0) return 1 ;;
  esac
  [[ -f "$APP_DIR/.env.prod" ]] &&
    grep -Eq '^[[:space:]]*OBSERVABILITY_ENABLED[[:space:]]*=[[:space:]]*(true|1)[[:space:]]*$' \
      "$APP_DIR/.env.prod"
}

switch_runtime() {
  local runtime_dir="$1"
  local link_path="$APP_DIR/runtime-current"
  local temporary_link="$APP_DIR/.runtime-current.$$"

  ln -s "$runtime_dir" "$temporary_link"
  if mv -Tf "$temporary_link" "$link_path" 2>/dev/null; then
    return 0
  fi
  mv -fh "$temporary_link" "$link_path"
}

compose_for_runtime() {
  local runtime_dir="$1"
  shift

  local profile_args=()
  local args=()
  if observability_enabled; then
    runtime_has_observability "$runtime_dir" || \
      die "observability is enabled but runtime files are incomplete: $runtime_dir"
    profile_args=(--profile observability)
    args+=(-f "$runtime_dir/observability/docker-compose.observability.yml")
  fi
  args+=(
    -f "$runtime_dir/docker-compose.prod.yml"
    -f "$runtime_dir/docker-compose.vm.yml"
  )

  docker compose \
    "${profile_args[@]}" \
    "${args[@]}" \
    --env-file "$APP_DIR/.env.prod" \
    "$@"
}

compose() {
  compose_for_runtime "$APP_DIR/runtime-current" "$@"
}

validate_backup_health_json() {
  python3 -c '
import json
import sys

data = json.load(sys.stdin)
allowed = {"never_run", "failed", "stale", "ready"}
assert data.get("status") in allowed, data.get("status")
assert isinstance(data.get("intervalHours"), int) and data["intervalHours"] > 0
assert "errorSummary" not in data
assert "bundlePath" not in data
assert "backupDir" not in data
assert "offsiteDir" not in data
drill = data.get("lastRecoveryDrill")
if drill is not None:
    assert drill.get("outcome") in {"success", "failed"}
    assert "errorSummary" not in drill
    assert "bundlePath" not in drill
'
}

verify_observability() {
  observability_enabled || return 0
  runtime_has_observability "$APP_DIR/runtime-current" || return 1

  local published
  local prometheus_url alertmanager_url grafana_url
  local prometheus_port alertmanager_port grafana_port
  local node_exporter_url cadvisor_url
  local node_exporter_port cadvisor_port
  local targets rules target_ready attempt

  published=$(compose port prometheus 9090) || return 1
  test -n "$published" || return 1
  prometheus_port=${published##*:}
  prometheus_url="http://127.0.0.1:${prometheus_port}"
  curl -fsS --retry 12 --retry-delay 5 --retry-connrefused \
    "$prometheus_url/-/ready" >/dev/null || return 1

  published=$(compose port alertmanager 9093) || return 1
  test -n "$published" || return 1
  alertmanager_port=${published##*:}
  alertmanager_url="http://127.0.0.1:${alertmanager_port}"
  curl -fsS --retry 12 --retry-delay 5 --retry-connrefused \
    "$alertmanager_url/-/ready" >/dev/null || return 1

  published=$(compose port node-exporter 9100) || return 1
  test -n "$published" || return 1
  node_exporter_port=${published##*:}
  node_exporter_url="http://127.0.0.1:${node_exporter_port}"
  curl -fsS --retry 12 --retry-delay 5 --retry-connrefused \
    "$node_exporter_url/-/healthy" >/dev/null || return 1

  published=$(compose port cadvisor 8080) || return 1
  test -n "$published" || return 1
  cadvisor_port=${published##*:}
  cadvisor_url="http://127.0.0.1:${cadvisor_port}"
  curl -fsS --retry 12 --retry-delay 5 --retry-connrefused \
    "$cadvisor_url/healthz" >/dev/null || return 1

  published=$(compose port grafana 3000) || return 1
  test -n "$published" || return 1
  grafana_port=${published##*:}
  grafana_url="http://127.0.0.1:${grafana_port}"
  curl -fsS --retry 12 --retry-delay 5 --retry-connrefused \
    "$grafana_url/api/health" | \
    python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["database"] == "ok"' || return 1

  target_ready=""
  for attempt in $(seq 1 12); do
    targets=$(curl -fsS "$prometheus_url/api/v1/targets?state=active") || return 1
    if printf '%s' "$targets" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["status"] == "success"
required_jobs = {"ledgerly-server", "node-exporter", "cadvisor"}
targets = {
    target["labels"].get("job"): target
    for target in data["data"]["activeTargets"]
    if target["labels"].get("job") in required_jobs
}
assert required_jobs <= targets.keys(), required_jobs - targets.keys()
assert all(target["health"] == "up" for target in targets.values())
'; then
      target_ready=1
      break
    fi
    sleep 5
  done
  test -n "$target_ready" || return 1

  rules=$(curl -fsS "$prometheus_url/api/v1/rules") || return 1
  printf '%s' "$rules" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["status"] == "success"
names = {
    rule["name"]
    for group in data["data"]["groups"]
    for rule in group["rules"]
    if rule.get("type") == "alerting"
}
required = {
    "LedgerlyBackupFailed",
    "LedgerlyAuditWriteFailures",
    "LedgerlyContainerOom",
    "LedgerlyFilesystemSpaceLow",
    "LedgerlyObjectStoreOperationFailures",
    "LedgerlyRecoveryDrillFailed",
    "LedgerlyServerDown",
    "LedgerlyHigh5xxRate",
}
assert required <= names, required - names
' || return 1
}

activate_runtime() {
  local release_dir="${1:?release directory is required}"
  local current_runtime

  test -f "$APP_DIR/.env.prod" || die "missing $APP_DIR/.env.prod"
  runtime_is_valid "$release_dir" || die "invalid runtime release: $release_dir"

  COMPOSE_PROJECT_NAME=ledgerly compose_for_runtime "$release_dir" config --quiet

  current_runtime=$(readlink "$APP_DIR/runtime-current" 2>/dev/null || true)
  if [[ "$current_runtime" == "$release_dir" ]]; then
    return 0
  fi
  if [[ -n "$current_runtime" ]]; then
    runtime_is_valid "$current_runtime" || die "invalid current runtime: $current_runtime"
  fi

  printf '%s\n' "$current_runtime" > "$APP_DIR/.previous-runtime"
  switch_runtime "$release_dir"
}

configure_backup_password() {
  local env_file="$APP_DIR/.env.prod"
  local temporary
  local backup_password
  local existing_password

  test -f "$env_file" || die "missing $env_file"
  IFS= read -r backup_password || die "missing backup password input"
  test -n "$backup_password" || die "empty backup password input"

  existing_password=$(sed -n \
    's/^[[:space:]]*LEDGER_BACKUP_PASSWORD[[:space:]]*=[[:space:]]*//p' \
    "$env_file" | tail -n 1)
  if [[ -n "$existing_password" &&
        "$existing_password" != "CHANGE_ME_BACKUP_PASSWORD" ]]; then
    printf 'LEDGER_BACKUP_PASSWORD is already configured\n'
    return 0
  fi

  umask 077
  temporary="${env_file}.tmp.$$"
  grep -vE '^[[:space:]]*LEDGER_BACKUP_PASSWORD[[:space:]]*=' \
    "$env_file" > "$temporary" || true
  printf 'LEDGER_BACKUP_PASSWORD=%s\n' "$backup_password" >> "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$env_file"
  printf 'LEDGER_BACKUP_PASSWORD configured\n'
}

read_deploy_input() {
  IFS= read -r GHCR_TOKEN || die "missing GHCR token input"
  IFS= read -r GHCR_USERNAME || die "missing GHCR username input"
  IFS= read -r SOURCE_IMAGE || die "missing source image input"
  IFS= read -r EXPECTED_IMAGE_PREFIX || die "missing image prefix input"

  test -n "$GHCR_TOKEN" || die "empty GHCR token"
  test -n "$GHCR_USERNAME" || die "empty GHCR username"
  test -n "$SOURCE_IMAGE" || die "empty source image"
}

deploy_and_verify() {
  printf 'deploy.verify compose\n' >&2
  compose up -d --pull never --wait --wait-timeout 180 || return 1

  local published port ready_url ready_body backup_url backup_body backup_status index_count
  printf 'deploy.verify ready\n' >&2
  published=$(compose port ledger-server 8080) || return 1
  test -n "$published" || return 1
  port=${published##*:}
  ready_url="http://127.0.0.1:${port}/health/ready"
  ready_body=$(curl -fsS --retry 5 --retry-delay 2 --retry-connrefused "$ready_url") || return 1
  printf '%s' "$ready_body" | python3 -c \
    'import json,sys; data=json.load(sys.stdin); assert data == {"status":"ready","store":"postgres"}' || return 1

  printf 'deploy.verify backup-health\n' >&2
  backup_url="http://127.0.0.1:${port}/health/backup"
  backup_body=$(curl -fsS --retry 5 --retry-delay 2 --retry-connrefused "$backup_url") || return 1
  printf '%s' "$backup_body" | validate_backup_health_json || return 1
  backup_status=$(printf '%s' "$backup_body" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["status"])') || return 1
  if [[ "$backup_status" != "ready" ]]; then
    printf 'WARNING: backup readiness is %s\n' "$backup_status" >&2
  fi

  printf 'deploy.verify writable-volumes\n' >&2
  compose exec -T ledger-server sh -c \
    'touch /var/lib/ledgerly/objects/.deploy-write-test && rm /var/lib/ledgerly/objects/.deploy-write-test && touch /var/lib/ledgerly/backups/.deploy-write-test && rm /var/lib/ledgerly/backups/.deploy-write-test && touch /var/lib/ledgerly/backups-offsite/.deploy-write-test && rm /var/lib/ledgerly/backups-offsite/.deploy-write-test' || return 1

  printf 'deploy.verify pg-dump\n' >&2
  compose exec -T ledger-server pg_dump --version | grep -Eiq 'postgresql\) 16' || return 1

  printf 'deploy.verify indexes\n' >&2
  index_count=$(compose exec -T postgres sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT count(*) FROM pg_indexes WHERE schemaname = '\''public'\'' AND indexname IN ('\''idx_device_sessions_refresh_token_hash'\'', '\''idx_device_sessions_active_created_at'\'');"') || return 1
  test "$index_count" = "2" || return 1

  printf 'deploy.verify observability\n' >&2
  verify_observability || return 1
}

deploy_release() {
  local deploy_image previous_image previous_runtime

  read_deploy_input
  runtime_is_valid "$(readlink "$APP_DIR/runtime-current" 2>/dev/null || true)" || \
    die "missing or invalid runtime-current"

  case "$SOURCE_IMAGE" in
    "$EXPECTED_IMAGE_PREFIX":*|"$EXPECTED_IMAGE_PREFIX"@sha256:*) ;;
    *) die "invalid deployment image: $SOURCE_IMAGE" ;;
  esac

  printf '%s' "$GHCR_TOKEN" | docker login ghcr.io \
    --username "$GHCR_USERNAME" --password-stdin >/dev/null
  trap 'docker logout ghcr.io >/dev/null 2>&1 || true' EXIT
  docker pull --platform linux/amd64 "$SOURCE_IMAGE"
  deploy_image="$SOURCE_IMAGE"
  docker image inspect "$deploy_image" >/dev/null

  if ! docker image inspect postgres:16-alpine >/dev/null 2>&1; then
    for attempt in 1 2 3 4 5; do
      docker pull postgres:16-alpine && break
      test "$attempt" -lt 5
      sleep $((attempt * 15))
    done
  fi

  export COMPOSE_PROJECT_NAME=ledgerly
  export LEDGER_IMAGE="$deploy_image"
  compose config --quiet
  previous_image=$(docker inspect --format '{{.Config.Image}}' ledgerly-server 2>/dev/null || true)
  previous_runtime=""
  if [[ -f "$APP_DIR/.previous-runtime" ]]; then
    previous_runtime=$(tr -d '\r\n' < "$APP_DIR/.previous-runtime")
  fi

  if ! deploy_and_verify; then
    compose logs --tail=150 ledger-server postgres prometheus alertmanager grafana || true
    if [[ -n "$previous_runtime" ]] && runtime_is_valid "$previous_runtime"; then
      printf 'Deployment failed; restoring runtime %s\n' "$previous_runtime"
      if ! runtime_has_observability "$previous_runtime"; then
        printf 'Previous runtime has no observability files; rolling back without the profile\n' >&2
        compose stop prometheus alertmanager grafana || true
        export OBSERVABILITY_ENABLED=false
      fi
      switch_runtime "$previous_runtime"
    fi
    if [[ -n "$previous_image" ]] && docker image inspect "$previous_image" >/dev/null 2>&1; then
      printf 'Deployment failed; restoring image %s\n' "$previous_image"
      export LEDGER_IMAGE="$previous_image"
      compose up -d --pull never --wait --wait-timeout 180 || true
    fi
    exit 1
  fi

  printf '%s\n' "$previous_image" > "$APP_DIR/.previous-image"
  printf '%s\n' "$deploy_image" > "$APP_DIR/.last-successful-image"
  compose ps
  compose logs --tail=50 ledger-server || true
  printf 'Deployed %s to %s\n' "$deploy_image" "$(hostname)"
}

main() {
  local command="${1:-}"
  APP_DIR="${3:-${2:-/opt/ledgerly}}"

  case "$command" in
    activate)
      activate_runtime "${2:?release directory is required}"
      ;;
    set-backup-password)
      configure_backup_password
      ;;
    deploy)
      deploy_release
      ;;
    *)
      die "usage: $0 activate RELEASE_DIR [APP_DIR] | set-backup-password [APP_DIR] | deploy [APP_DIR]"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
