#!/usr/bin/env bash
# Deploy ledger-server image to a remote host that already runs PostgreSQL.
# Secrets via env (do not commit passwords):
#   DEPLOY_HOST DEPLOY_USER DEPLOY_SSH_KEY_FILE
#   LEDGER_IMAGE (optional) DEPLOY_DIR (default /opt/ledgerly)
set -euo pipefail

HOST="${DEPLOY_HOST:?set DEPLOY_HOST}"
USER="${DEPLOY_USER:?set DEPLOY_USER}"
KEY="${DEPLOY_SSH_KEY_FILE:?set DEPLOY_SSH_KEY_FILE}"
PORT="${DEPLOY_SSH_PORT:-22}"
DIR="${DEPLOY_DIR:-/opt/ledgerly}"
IMAGE="${LEDGER_IMAGE:-ghcr.io/baicie/ledgerly-server:latest}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ssh_base=(ssh -i "$KEY" -p "$PORT" -o StrictHostKeyChecking=accept-new "${USER}@${HOST}")
scp_base=(scp -i "$KEY" -P "$PORT" -o StrictHostKeyChecking=accept-new)

echo "==> ensure remote dir $DIR"
"${ssh_base[@]}" "mkdir -p '$DIR' '$DIR/observability'"

echo "==> sync compose file"
"${scp_base[@]}" \
  "$REPO_ROOT/infrastructure/docker/docker-compose.prod.yml" \
  "${USER}@${HOST}:$DIR/docker-compose.prod.yml"
"${scp_base[@]}" -r \
  "$REPO_ROOT/infrastructure/observability/." \
  "${USER}@${HOST}:$DIR/observability/"

echo "==> remote pull & up ($IMAGE)"
"${ssh_base[@]}" bash -s <<EOF
set -euo pipefail
cd '$DIR'
test -f .env.prod || { echo 'Create $DIR/.env.prod from env.prod.example first'; exit 1; }
# shellcheck disable=SC1091
set -a; source .env.prod; set +a
export LEDGER_IMAGE='$IMAGE'
export COMPOSE_PROJECT_NAME=ledgerly
compose_args=(-f docker-compose.prod.yml)
if [[ "\${OBSERVABILITY_ENABLED:-false}" =~ ^(true|1)$ ]]; then
  compose_args=(--profile observability -f observability/docker-compose.observability.yml -f docker-compose.prod.yml)
fi
docker compose "\${compose_args[@]}" --env-file .env.prod pull
docker compose "\${compose_args[@]}" --env-file .env.prod up -d --wait --wait-timeout 180
docker compose "\${compose_args[@]}" --env-file .env.prod ps
curl -sf "http://127.0.0.1:\${LEDGER_PORT:-8080}/health/ready"
curl -sf "http://127.0.0.1:\${LEDGER_PORT:-8080}/health/backup" | \
  python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["status"] in {"never_run","failed","stale","ready"}; assert "bundlePath" not in data'
docker compose "\${compose_args[@]}" --env-file .env.prod exec -T ledger-server sh -c \
  'touch /var/lib/ledgerly/backups/.deploy-write-test && rm /var/lib/ledgerly/backups/.deploy-write-test && touch /var/lib/ledgerly/backups-offsite/.deploy-write-test && rm /var/lib/ledgerly/backups-offsite/.deploy-write-test'
if [[ "\${OBSERVABILITY_ENABLED:-false}" =~ ^(true|1)$ ]]; then
  curl -sf "http://127.0.0.1:\${PROMETHEUS_PORT:-9090}/-/ready" >/dev/null
  curl -sf "http://127.0.0.1:\${NODE_EXPORTER_PORT:-9100}/-/healthy" >/dev/null
  curl -sf "http://127.0.0.1:\${CADVISOR_PORT:-8082}/healthz" >/dev/null
  curl -sf "http://127.0.0.1:\${ALERTMANAGER_PORT:-9093}/-/ready" >/dev/null
  curl -sf "http://127.0.0.1:\${GRAFANA_PORT:-3000}/api/health" | \
    python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["database"] == "ok"'
fi
echo
echo OK
EOF
