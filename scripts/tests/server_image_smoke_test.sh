#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?usage: server_image_smoke_test.sh IMAGE}"
RUN_ID="${GITHUB_RUN_ID:-local}-$$"
OBJECT_VOLUME="ledgerly-image-smoke-objects-${RUN_ID}"
BACKUP_VOLUME="ledgerly-image-smoke-backups-${RUN_ID}"
OFFSITE_VOLUME="ledgerly-image-smoke-offsite-${RUN_ID}"

cleanup() {
  docker volume rm \
    "$OBJECT_VOLUME" "$BACKUP_VOLUME" "$OFFSITE_VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$OBJECT_VOLUME" >/dev/null
docker volume create "$BACKUP_VOLUME" >/dev/null
docker volume create "$OFFSITE_VOLUME" >/dev/null
docker run --rm \
  --volume "$OBJECT_VOLUME:/var/lib/ledgerly/objects" \
  --volume "$BACKUP_VOLUME:/var/lib/ledgerly/backups" \
  --volume "$OFFSITE_VOLUME:/var/lib/ledgerly/backups-offsite" \
  --entrypoint sh \
  "$IMAGE" \
  -c '
    set -eu
    test "$(id -u)" = 10001
    touch /var/lib/ledgerly/objects/.write-test
    touch /var/lib/ledgerly/backups/.write-test
    touch /var/lib/ledgerly/backups-offsite/.write-test
    pg_dump --version | grep -Ei "postgresql\) 16" >/dev/null
    pg_restore --version | grep -Ei "postgresql\) 16" >/dev/null
  '
