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

pg_prove -d "$DB" supabase/tests/database/*.test.sql
