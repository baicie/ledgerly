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
touch "$APP_DIR/.env.prod"
for release in "$FIRST_RELEASE" "$SECOND_RELEASE"; do
  touch "$release/docker-compose.prod.yml" "$release/docker-compose.vm.yml"
done

docker() {
  return 0
}

activate_runtime "$FIRST_RELEASE"
test "$(readlink "$APP_DIR/runtime-current")" = "$FIRST_RELEASE"

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
