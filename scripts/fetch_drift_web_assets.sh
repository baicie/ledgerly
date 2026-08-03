#!/usr/bin/env bash
# Fetch drift/sqlite3 web assets into apps/client/web/.
# Keep versions aligned with pubspec.lock (drift / sqlite3).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/apps/client/web"
DRIFT_TAG="${DRIFT_TAG:-drift-2.31.0}"
SQLITE3_TAG="${SQLITE3_TAG:-sqlite3-2.9.4}"

mkdir -p "$WEB"
curl -fsSL -o "$WEB/sqlite3.wasm" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/${SQLITE3_TAG}/sqlite3.wasm"
curl -fsSL -o "$WEB/drift_worker.js" \
  "https://github.com/simolus3/drift/releases/download/${DRIFT_TAG}/drift_worker.js"
ls -lh "$WEB/sqlite3.wasm" "$WEB/drift_worker.js"
