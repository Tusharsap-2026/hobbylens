#!/usr/bin/env bash
# Runs the database tests against a throw-away database on a local PostgreSQL + PostGIS server.
# Usage: PGHOST=/tmp PGPORT=54322 tools/db/test.sh
# In a Supabase project you can instead run `supabase test db` (the shim is then not needed).
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${PGUSER:=postgres}"
DB="${TEST_DB:-hobbylens_test}"
export PGUSER

psql -q -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
run() { psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$1" >/dev/null; }

run tools/db/supabase_shim.sql
for f in supabase/migrations/*.sql; do echo "migrate  $f"; run "$f"; done
echo "seed     supabase/seed.sql"; run supabase/seed.sql
psql -q -d "$DB" -c "create extension if not exists pgtap" >/dev/null

if command -v pg_prove >/dev/null 2>&1; then
  pg_prove -d "$DB" supabase/tests/database/*.test.sql
else
  # Fallback without pg_prove: run each file with psql and fail on any "not ok" or plan mismatch.
  failed=0
  for f in supabase/tests/database/*.test.sql; do
    out=$(psql -X -q -At -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1) || { echo "FAIL $f"; echo "$out"; failed=1; continue; }
    if echo "$out" | grep -Eq '^not ok|Looks like you planned'; then echo "FAIL $f"; echo "$out" | grep -E '^not ok|#'; failed=1
    else echo "ok   $f ($(echo "$out" | grep -c '^ok') tests)"; fi
  done
  exit $failed
fi
