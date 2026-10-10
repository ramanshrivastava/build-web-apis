#!/usr/bin/env bash
# Apply db/migrations/NNNN_name.sql in order, each exactly once.
#
#   scripts/migrate.sh            # apply pending migrations
#   scripts/migrate.sh --seed     # ...then apply db/seed.sql (must be idempotent)
#
# Applied versions are recorded in schema_migrations, so re-running is a no-op.
# Each file runs in one transaction together with its schema_migrations row:
# do not put BEGIN/COMMIT or CREATE INDEX CONCURRENTLY in a migration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATABASE_URL="${DATABASE_URL:-postgres://postgres:ticketing@localhost:5432/ticketing}"
SEED=0
for arg in "$@"; do
  case "$arg" in
    --seed) SEED=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "migrate: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

if ! command -v psql >/dev/null 2>&1; then
  echo "migrate: psql not found (brew install libpq, apt install postgresql-client, or run in 'just lab')" >&2
  exit 1
fi

psql_q() { psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 "$@"; }

psql_q -c "SET client_min_messages TO warning;
CREATE TABLE IF NOT EXISTS schema_migrations (
  version    text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
)"

applied=0
skipped=0
for file in "$ROOT"/db/migrations/*.sql; do
  [ -e "$file" ] || break # no migrations yet
  version="$(basename "$file" .sql)"
  if ! [[ "$version" =~ ^[0-9]{4}_[a-z0-9_]+$ ]]; then
    echo "migrate: bad file name '$version.sql' (want NNNN_snake_case.sql)" >&2
    exit 1
  fi
  if [ "$(psql_q -tA -c "SELECT 1 FROM schema_migrations WHERE version = '$version'")" = "1" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  echo "migrate: apply $version"
  psql_q --single-transaction -f "$file" \
    -c "INSERT INTO schema_migrations (version) VALUES ('$version')"
  applied=$((applied + 1))
done
echo "migrate: $applied applied, $skipped already applied"

if [ "$SEED" = 1 ]; then
  echo "migrate: seed db/seed.sql"
  psql_q --single-transaction -f "$ROOT/db/seed.sql"
fi
