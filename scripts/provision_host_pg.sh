#!/usr/bin/env bash
# One-time: create ledgerly role/db on an existing PostgreSQL instance.
# Usage (on the DB host or with psql reachable):
#   PGHOST=127.0.0.1 PGUSER=postgres ./scripts/provision_host_pg.sh
set -euo pipefail

DB_NAME="${LEDGER_DB_NAME:-ledgerly}"
DB_USER="${LEDGER_DB_USER:-ledgerly}"
DB_PASS="${LEDGER_DB_PASSWORD:?set LEDGER_DB_PASSWORD}"

psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL

echo "Provisioned database ${DB_NAME} owner ${DB_USER}"
echo "Use DATABASE_URL=postgres://${DB_USER}:***@host.docker.internal:5432/${DB_NAME}"
