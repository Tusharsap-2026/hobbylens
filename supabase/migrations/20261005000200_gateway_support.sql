-- Support objects for the edge functions (service role only).

-- AI-written care tips for species outside the curated list, cached so each species is
-- generated once. Shown in the app with an "AI-generated, not reviewed" label. An admin can
-- promote a good entry into a curated care card.
create table public.ai_care_cache (
  kind            public.taxon_kind not null,
  scientific_name text not null,
  tips            jsonb not null check (jsonb_typeof(tips) = 'array'),
  model           text not null,
  created_at      timestamptz not null default now(),
  primary key (kind, scientific_name)
);
alter table public.ai_care_cache enable row level security;
create policy ai_care_cache_admin on public.ai_care_cache for all
  using (public.is_admin()) with check (public.is_admin());

-- Anonymous guest accounts not seen for a while, so the cleanup job can delete them.
create or replace function public.stale_anonymous_users(p_days integer default 30, p_limit integer default 200)
returns table (user_id uuid) language sql stable security definer set search_path = '' as $$
  select u.id from auth.users u
  where u.is_anonymous
    and coalesce(u.last_sign_in_at, u.created_at) < now() - make_interval(days => p_days)
  order by coalesce(u.last_sign_in_at, u.created_at)
  limit p_limit
$$;
revoke execute on function public.stale_anonymous_users(integer, integer) from public, anon, authenticated;
grant execute on function public.stale_anonymous_users(integer, integer) to service_role;
