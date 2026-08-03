#!/usr/bin/env bash
# Simple sync load smoke: register/login/push N times against local server.
set -euo pipefail
BASE="${LEDGER_BASE:-http://127.0.0.1:8080}"
N="${1:-20}"
echo "loadtest against $BASE count=$N"
for i in $(seq 1 "$N"); do
  email="load_${i}_$(date +%s)@test.local"
  curl -sf -X POST "$BASE/v1/auth/register" \
    -H 'content-type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"password123\",\"displayName\":\"L$i\"}" >/dev/null || true
  login=$(curl -sf -X POST "$BASE/v1/auth/login" \
    -H 'content-type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"password123\",\"deviceId\":\"dev$i\"}")
  token=$(echo "$login" | python3 -c 'import sys,json; print(json.load(sys.stdin)["accessToken"])')
  book=$(echo "$login" | python3 -c 'import sys,json; print(json.load(sys.stdin)["bookId"])')
  food="$book:acc_food"
  cash="$book:acc_cash"
  curl -sf -X POST "$BASE/v1/books/$book/sync/push" \
    -H "authorization: Bearer $token" \
    -H 'content-type: application/json' \
    -d "{\"deviceId\":\"dev$i\",\"mutations\":[{\"mutationId\":\"m$i\",\"entityType\":\"transaction\",\"entityId\":\"tx$i\",\"operation\":\"create\",\"baseVersion\":0,\"schemaVersion\":1,\"payload\":{\"description\":\"load\",\"entries\":[{\"accountId\":\"$food\",\"amountMinor\":\"100\",\"currency\":\"CNY\"},{\"accountId\":\"$cash\",\"amountMinor\":\"-100\",\"currency\":\"CNY\"}]}}]}" >/dev/null
  echo "ok $i"
done
echo "done"
