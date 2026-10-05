#!/usr/bin/env bash
# Integration test of the edge-function database layer against PostgreSQL + PostgREST.
# Needs: a local PostgreSQL with PostGIS (PGHOST/PGPORT), the `postgrest` binary, and Deno.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${PGUSER:=postgres}"
export PGUSER
DB="${TEST_DB:-hobbylens_it}"
PGRST_PORT="${PGRST_PORT:-54401}"
JWT_SECRET="integration-test-secret-at-least-32-characters"

psql -q -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
run() { psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$1" >/dev/null; }
run tools/db/supabase_shim.sql
for f in supabase/migrations/*.sql; do run "$f"; done
run supabase/seed.sql
psql -q -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit password 'authenticator-test';
  end if;
end $$;
grant anon, authenticated, service_role to authenticator;
insert into auth.users (id, phone) values ('44444444-4444-4444-8444-444444444444', '+8801744444444');
SQL

HOST_ARG="${PGHOST:-localhost}"
cat > /tmp/pgrst_it.conf <<EOF
db-uri = "postgres://authenticator:authenticator-test@/$DB?host=$HOST_ARG&port=${PGPORT:-5432}"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "$JWT_SECRET"
server-port = $PGRST_PORT
server-host = "127.0.0.1"
EOF
postgrest /tmp/pgrst_it.conf > /tmp/pgrst_it.log 2>&1 &
PGRST_PID=$!
trap 'kill $PGRST_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do curl -sf "http://127.0.0.1:$PGRST_PORT/" >/dev/null && break; sleep 0.2; done

cd supabase/functions
PGRST_PORT=$PGRST_PORT PGRST_JWT_SECRET=$JWT_SECRET deno test --allow-env --allow-net tests_integration/

if [ "${MAKE_FIXTURES:-0}" = "1" ]; then
  PGRST_PORT=$PGRST_PORT PGRST_JWT_SECRET=$JWT_SECRET FIXTURE_DIR=../../app/test/fixtures \
    deno run --allow-env --allow-net --allow-write=../../app/test/fixtures --allow-read tests_integration/make_fixtures.ts
fi
