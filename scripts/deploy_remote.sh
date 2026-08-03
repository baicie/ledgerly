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
"${ssh_base[@]}" "mkdir -p '$DIR'"

echo "==> sync compose file"
"${scp_base[@]}" \
  "$REPO_ROOT/infrastructure/docker/docker-compose.prod.yml" \
  "${USER}@${HOST}:$DIR/docker-compose.prod.yml"

echo "==> remote pull & up ($IMAGE)"
"${ssh_base[@]}" bash -s <<EOF
set -euo pipefail
cd '$DIR'
test -f .env.prod || { echo 'Create $DIR/.env.prod from .env.prod.example first'; exit 1; }
export LEDGER_IMAGE='$IMAGE'
# shellcheck disable=SC1091
set -a; source .env.prod; set +a
docker compose -f docker-compose.prod.yml --env-file .env.prod pull
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d
docker compose -f docker-compose.prod.yml --env-file .env.prod ps
curl -sf "http://127.0.0.1:\${LEDGER_PORT:-8080}/health/ready"
echo
echo OK
EOF
