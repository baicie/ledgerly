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

compose() {
  docker compose \
    -f "$APP_DIR/runtime-current/docker-compose.prod.yml" \
    -f "$APP_DIR/runtime-current/docker-compose.vm.yml" \
    --env-file "$APP_DIR/.env.prod" \
    "$@"
}

activate_runtime() {
  local release_dir="${1:?release directory is required}"
  local current_runtime

  test -f "$APP_DIR/.env.prod" || die "missing $APP_DIR/.env.prod"
  runtime_is_valid "$release_dir" || die "invalid runtime release: $release_dir"

  COMPOSE_PROJECT_NAME=ledgerly docker compose \
    -f "$release_dir/docker-compose.prod.yml" \
    -f "$release_dir/docker-compose.vm.yml" \
    --env-file "$APP_DIR/.env.prod" \
    config --quiet

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
  compose up -d --pull never --wait --wait-timeout 180 || return 1

  local published port ready_url ready_body index_count
  published=$(compose port ledger-server 8080) || return 1
  test -n "$published" || return 1
  port=${published##*:}
  ready_url="http://127.0.0.1:${port}/health/ready"
  ready_body=$(curl -fsS --retry 5 --retry-delay 2 --retry-connrefused "$ready_url") || return 1
  printf '%s' "$ready_body" | python3 -c \
    'import json,sys; data=json.load(sys.stdin); assert data == {"status":"ready","store":"postgres"}' || return 1

  compose exec -T ledger-server sh -c \
    'touch /var/lib/ledgerly/objects/.deploy-write-test && rm /var/lib/ledgerly/objects/.deploy-write-test' || return 1

  index_count=$(compose exec -T postgres sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT count(*) FROM pg_indexes WHERE schemaname = '\''public'\'' AND indexname IN ('\''idx_device_sessions_refresh_token_hash'\'', '\''idx_device_sessions_active_created_at'\'');"') || return 1
  test "$index_count" = "2" || return 1
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
    compose logs --tail=150 ledger-server postgres || true
    if [[ -n "$previous_runtime" ]] && runtime_is_valid "$previous_runtime"; then
      printf 'Deployment failed; restoring runtime %s\n' "$previous_runtime"
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
    deploy)
      deploy_release
      ;;
    *)
      die "usage: $0 activate RELEASE_DIR [APP_DIR] | deploy [APP_DIR]"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
