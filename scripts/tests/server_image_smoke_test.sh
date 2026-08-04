#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?usage: server_image_smoke_test.sh IMAGE}"
RUN_ID="${GITHUB_RUN_ID:-local}-$$"
VOLUME="ledgerly-image-smoke-${RUN_ID}"

cleanup() {
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$VOLUME" >/dev/null
docker run --rm \
  --volume "$VOLUME:/var/lib/ledgerly/objects" \
  --entrypoint sh \
  "$IMAGE" \
  -c 'test "$(id -u)" = 10001 && touch /var/lib/ledgerly/objects/.write-test'
