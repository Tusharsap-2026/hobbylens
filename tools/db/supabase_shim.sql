-- Local stand-in for the parts of Supabase the migrations depend on.
-- Used ONLY by tools/db/test.sh against a plain PostgreSQL + PostGIS server.
-- Never run this against a real Supabase project: there these objects already exist.

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists extensions;
create schema if not exists auth;
create schema if not exists storage;

grant usage on schema public, extensions to anon, authenticated, service_role;

-- Supabase grants table, sequence and function privileges to its API roles by default and
-- relies on row-level security to restrict them. Mirror that here.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
grant usage on schema auth, storage to anon, authenticated, service_role;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  phone text unique,
  is_anonymous boolean not null default false,
  created_at timestamptz not null default now(),
  last_sign_in_at timestamptz
);

-- Supabase reads the caller's JWT claims from these settings.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text not null,
  owner uuid,
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;

create or replace function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;

-- Test helper: act as a given user (or as anon when uid is null).
create or replace function public._test_login(p_uid uuid, p_anonymous boolean default false) returns void
language plpgsql as $$
begin
  if p_uid is null then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', 'authenticated', 'is_anonymous', p_anonymous)::text, true);
    execute 'set local role authenticated';
  end if;
end $$;
