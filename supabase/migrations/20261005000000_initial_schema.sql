-- HobbyLens: initial schema (Phase 1, with the Phase 2 partner_stock table designed in).
-- Target: Supabase (PostgreSQL 15+ with PostGIS in the "extensions" schema).
--
-- Identity model
--   * Every app install signs in anonymously on first launch (Supabase anonymous sign-in),
--     so guests get a real user id and row-level security applies to everyone.
--   * At the first "Save to My Collection" the app links a phone number (OTP). The user id
--     does not change, so earlier identifications stay with the person.
--   * Saving to My Collection is refused for anonymous users at the database level.

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.taxon_kind     as enum ('plant', 'cat', 'dog', 'bird');
create type public.id_category    as enum ('plant', 'cat', 'dog', 'bird', 'auto');
create type public.id_status      as enum ('confident', 'low_confidence', 'not_recognised', 'failed');
create type public.pet_safety     as enum ('safe', 'toxic_cats', 'toxic_dogs', 'toxic_both', 'unknown');
create type public.shop_type      as enum ('nursery', 'pet_shop', 'vet_supply', 'vet_clinic');
create type public.content_status as enum ('draft', 'reviewed', 'ai_generated');
create type public.care_topic     as enum ('light', 'water', 'soil', 'temperature', 'fertiliser',
                                           'food', 'space', 'grooming', 'exercise', 'vaccination');
create type public.reminder_type  as enum ('water', 'fertilise', 'feed', 'groom', 'vaccinate', 'custom');
create type public.flag_reason    as enum ('wrong_match', 'not_a_plant_or_pet', 'other');
create type public.flag_status    as enum ('open', 'confirmed', 'dismissed');
create type public.contact_action as enum ('view', 'call', 'whatsapp', 'directions');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create table public.app_admins (
  user_id  uuid primary key references auth.users (id) on delete cascade,
  added_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_admins a where a.user_id = auth.uid())
$$;

-- True when the caller is signed in with a phone (not an anonymous guest session).
create or replace function public.is_registered() returns boolean
language sql stable set search_path = '' as $$
  select auth.uid() is not null
     and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
$$;

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  language   text not null default 'bn' check (language in ('bn', 'en')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Reference content: species and breeds, care cards, catalogue
-- ---------------------------------------------------------------------------
create table public.catalogue_categories (
  id        bigint generated always as identity primary key,
  slug      text not null unique check (slug ~ '^[a-z0-9_]+$'),
  name_en   text not null,
  name_bn   text not null,
  kinds     public.taxon_kind[] not null check (cardinality(kinds) > 0),
  -- false = a kind of live plant a nursery sells (used to match shops);
  -- true  = a supply shown in "What you'll need".
  is_supply boolean not null default true,
  sort      smallint not null default 0
);

create table public.taxa (
  id                bigint generated always as identity primary key,
  key               text not null unique check (key ~ '^[a-z0-9_]+$'),
  kind              public.taxon_kind not null,
  rank              text not null check (rank in ('species', 'genus', 'breed', 'landrace')),
  scientific_name   text not null,
  name_en           text not null,
  name_bn           text not null,
  genus             text,
  family            text,
  -- Lower-case names an engine may return for this taxon: scientific names, synonyms,
  -- English common names, breed names. Used by match_taxon().
  match_names       text[] not null default '{}',
  pet_safety        public.pet_safety,
  -- For plants: which live-plant category a nursery must stock to be a "likely" seller.
  shop_category_id  bigint references public.catalogue_categories (id) on delete set null,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (kind = 'plant' or pet_safety is null)
);
create index taxa_match_names_gin on public.taxa using gin (match_names);
create index taxa_genus_idx on public.taxa (lower(genus)) where rank = 'genus';
create trigger taxa_touch before update on public.taxa
  for each row execute function public.touch_updated_at();

-- A care card belongs to one taxon, or to a whole kind as the fallback (e.g. "cat").
create table public.care_cards (
  id           bigint generated always as identity primary key,
  taxon_id     bigint references public.taxa (id) on delete cascade,
  kind         public.taxon_kind,
  status       public.content_status not null default 'draft',
  reviewed_by  text,
  reviewed_at  timestamptz,
  generated_by text,
  updated_at   timestamptz not null default now(),
  check ((taxon_id is null) <> (kind is null)),
  check (status <> 'reviewed' or (reviewed_by is not null and reviewed_at is not null))
);
create unique index care_cards_taxon_uq on public.care_cards (taxon_id) where taxon_id is not null;
create unique index care_cards_kind_uq on public.care_cards (kind) where kind is not null;
create trigger care_cards_touch before update on public.care_cards
  for each row execute function public.touch_updated_at();

create table public.care_tips (
  id           bigint generated always as identity primary key,
  care_card_id bigint not null references public.care_cards (id) on delete cascade,
  topic        public.care_topic not null,
  body_en      text not null check (char_length(body_en) between 3 and 400),
  body_bn      text not null check (char_length(body_bn) between 3 and 400),
  sort         smallint not null default 0,
  unique (care_card_id, topic)
);

create table public.catalogue_items (
  id              bigint generated always as identity primary key,
  category_id     bigint not null references public.catalogue_categories (id) on delete restrict,
  name_en         text not null,
  name_bn         text not null,
  description_en  text,
  description_bn  text,
  -- Indicative price range in BDT. Null until checked in the shop survey; the app then
  -- shows "ask the shop" instead of inventing a price.
  price_min_bdt   integer check (price_min_bdt >= 0),
  price_max_bdt   integer check (price_max_bdt >= 0),
  price_checked_on date,
  photo_path      text,
  is_active       boolean not null default true,
  sort            smallint not null default 0,
  check (price_min_bdt is null or price_max_bdt is null or price_max_bdt >= price_min_bdt)
);

-- Which plants or animals an item suits: one taxon, or a whole kind.
create table public.catalogue_item_suits (
  id        bigint generated always as identity primary key,
  item_id   bigint not null references public.catalogue_items (id) on delete cascade,
  taxon_id  bigint references public.taxa (id) on delete cascade,
  kind      public.taxon_kind,
  essential boolean not null default false,
  check ((taxon_id is null) <> (kind is null)),
  unique nulls not distinct (item_id, taxon_id, kind)
);

-- ---------------------------------------------------------------------------
-- Identifications
-- ---------------------------------------------------------------------------
create table public.identifications (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users (id) on delete cascade,
  requested_category public.id_category not null,
  detected_category  public.taxon_kind,
  status             public.id_status not null,
  engine             text not null,
  top_confidence     numeric(5, 4) check (top_confidence between 0 and 1),
  response_ms        integer check (response_ms >= 0),
  cost_usd           numeric(10, 6) not null default 0,
  photo_path         text,
  photo_expires_at   timestamptz,
  client_hint        jsonb,
  created_at         timestamptz not null default now()
);
create index identifications_user_idx on public.identifications (user_id, created_at desc);
create index identifications_created_idx on public.identifications (created_at);
create index identifications_photo_expiry_idx on public.identifications (photo_expires_at)
  where photo_path is not null;

create table public.identification_matches (
  identification_id uuid not null references public.identifications (id) on delete cascade,
  rank              smallint not null check (rank between 1 and 3),
  taxon_id          bigint references public.taxa (id) on delete set null,
  raw_name          text not null,
  raw_common_name   text,
  confidence        numeric(5, 4) check (confidence between 0 and 1),
  confidence_band   text check (confidence_band in ('high', 'medium', 'low')),
  primary key (identification_id, rank)
);

-- Daily usage per subject ('u:<user id>' or 'ip:<hash>'), written only by the gateway.
create table public.usage_counters (
  subject text not null,
  day     date not null,
  count   integer not null default 0,
  primary key (subject, day)
);

create table public.flags (
  id                uuid primary key default gen_random_uuid(),
  identification_id uuid not null references public.identifications (id) on delete cascade,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  reason            public.flag_reason not null,
  note              text check (char_length(note) <= 500),
  suggested_name    text check (char_length(suggested_name) <= 120),
  status            public.flag_status not null default 'open',
  correct_taxon_id  bigint references public.taxa (id) on delete set null,
  resolved_by       uuid references auth.users (id) on delete set null,
  resolved_at       timestamptz,
  created_at        timestamptz not null default now(),
  unique (identification_id, user_id)
);
create index flags_open_idx on public.flags (created_at) where status = 'open';

-- ---------------------------------------------------------------------------
-- My Collection (offline-first: ids are generated on the phone)
-- ---------------------------------------------------------------------------
create table public.collection_items (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind              public.taxon_kind not null,
  taxon_id          bigint references public.taxa (id) on delete set null,
  identification_id uuid references public.identifications (id) on delete set null,
  -- Names as shown when saved, so species outside our list still display correctly.
  scientific_name   text check (char_length(scientific_name) <= 120),
  name_en           text check (char_length(name_en) <= 120),
  name_bn           text check (char_length(name_bn) <= 120),
  nickname          text check (char_length(nickname) <= 60),
  photo_path        text,
  acquired_on       date,
  notes             text check (char_length(notes) <= 1000),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index collection_items_user_idx on public.collection_items (user_id, updated_at);
create trigger collection_items_touch before update on public.collection_items
  for each row execute function public.touch_updated_at();

create table public.reminders (
  id                 uuid primary key,
  collection_item_id uuid not null references public.collection_items (id) on delete cascade,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type               public.reminder_type not null,
  label              text check (char_length(label) <= 60),
  every_days         smallint check (every_days between 1 and 365),
  next_due           date not null,
  remind_at          time not null default '09:00',
  enabled            boolean not null default true,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
create index reminders_user_idx on public.reminders (user_id, updated_at);
create trigger reminders_touch before update on public.reminders
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Shops (our own field-verified directory; Google place id is the only Google field kept)
-- ---------------------------------------------------------------------------
create table public.shops (
  id              uuid primary key default gen_random_uuid(),
  name_en         text not null,
  name_bn         text,
  shop_type       public.shop_type not null,
  location        extensions.geography(point, 4326) not null,
  address_en      text,
  address_bn      text,
  area            text,
  city            text not null,
  phone           text check (phone ~ '^\+880[0-9]{8,10}$'),
  whatsapp        text check (whatsapp ~ '^\+8801[3-9][0-9]{8}$'),
  -- Opening hours in Bangladesh local time, e.g. {"sat":[["09:00","21:00"]], "fri":[]}.
  -- A missing day means closed; a null value means hours are unknown.
  opening_hours   jsonb,
  photos          text[] not null default '{}',
  rating          numeric(2, 1) check (rating between 1 and 5),
  rating_count    integer not null default 0,
  google_place_id text unique,
  verified_at     timestamptz,
  consent_at      timestamptz,
  is_partner      boolean not null default false,
  status          text not null default 'active' check (status in ('active', 'closed', 'hidden')),
  is_demo         boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index shops_location_gix on public.shops using gist (location);
create index shops_type_idx on public.shops (shop_type) where status = 'active';
create trigger shops_touch before update on public.shops
  for each row execute function public.touch_updated_at();

create table public.shop_categories (
  shop_id     uuid not null references public.shops (id) on delete cascade,
  category_id bigint not null references public.catalogue_categories (id) on delete cascade,
  primary key (shop_id, category_id)
);

-- Phase 2: stock confirmed by partner shops. A badge shows only while confirmed_at < 14 days old.
create table public.partner_stock (
  id           bigint generated always as identity primary key,
  shop_id      uuid not null references public.shops (id) on delete cascade,
  taxon_id     bigint references public.taxa (id) on delete cascade,
  item_id      bigint references public.catalogue_items (id) on delete cascade,
  price_bdt    integer check (price_bdt >= 0),
  in_stock     boolean not null default true,
  photo_path   text,
  confirmed_at timestamptz not null default now(),
  check ((taxon_id is null) <> (item_id is null)),
  unique nulls not distinct (shop_id, taxon_id, item_id)
);

-- ---------------------------------------------------------------------------
-- Analytics events the brief asks for (no user location is stored)
-- ---------------------------------------------------------------------------
create table public.search_events (
  id           bigint generated always as identity primary key,
  user_id      uuid references auth.users (id) on delete cascade,
  kind         public.taxon_kind,
  taxon_id     bigint references public.taxa (id) on delete set null,
  radius_km    smallint not null,
  result_count smallint not null,
  created_at   timestamptz not null default now()
);
create index search_events_created_idx on public.search_events (created_at);

create table public.shop_contact_events (
  id         bigint generated always as identity primary key,
  shop_id    uuid not null references public.shops (id) on delete cascade,
  user_id    uuid references auth.users (id) on delete cascade,
  action     public.contact_action not null,
  created_at timestamptz not null default now()
);
create index shop_contact_events_shop_idx on public.shop_contact_events (shop_id, created_at);
create index shop_contact_events_created_idx on public.shop_contact_events (created_at);

-- ---------------------------------------------------------------------------
-- Functions used by the app
-- ---------------------------------------------------------------------------

-- Is a shop open at a given moment? Null when hours are unknown. Handles overnight slots.
create or replace function public.shop_open_now(p_hours jsonb, p_at timestamptz default now())
returns boolean language plpgsql stable set search_path = '' as $$
declare
  v_local     timestamp := p_at at time zone 'Asia/Dhaka';
  v_t         time := v_local::time;
  v_today     text := to_char(v_local, 'dy');
  v_yesterday text := to_char(v_local - interval '1 day', 'dy');
  v_slot      jsonb;
  v_open      time;
  v_close     time;
begin
  if p_hours is null or jsonb_typeof(p_hours) <> 'object' then
    return null;
  end if;
  for v_slot in select value from jsonb_array_elements(coalesce(p_hours -> v_today, '[]'::jsonb)) loop
    v_open := (v_slot ->> 0)::time;
    v_close := (v_slot ->> 1)::time;
    if v_close > v_open then
      if v_t >= v_open and v_t < v_close then return true; end if;
    elsif v_t >= v_open then
      return true; -- overnight slot, evening part
    end if;
  end loop;
  for v_slot in select value from jsonb_array_elements(coalesce(p_hours -> v_yesterday, '[]'::jsonb)) loop
    v_open := (v_slot ->> 0)::time;
    v_close := (v_slot ->> 1)::time;
    if v_close <= v_open and v_t < v_close then
      return true; -- overnight slot that started yesterday
    end if;
  end loop;
  return false;
end $$;

-- Shops near a point, ranked: confirmed partner stock first, then category match, then distance.
create or replace function public.nearby_shops(
  p_lat       double precision,
  p_lng       double precision,
  p_radius_km integer,
  p_kind      public.taxon_kind default null,
  p_taxon_id  bigint default null,
  p_types     public.shop_type[] default null,
  p_limit     integer default 30
)
returns table (
  id                 uuid,
  name_en            text,
  name_bn            text,
  shop_type          public.shop_type,
  lat                double precision,
  lng                double precision,
  distance_m         integer,
  address_en         text,
  address_bn         text,
  area               text,
  phone              text,
  whatsapp           text,
  opening_hours      jsonb,
  open_now           boolean,
  rating             numeric,
  rating_count       integer,
  verified_at        timestamptz,
  is_partner         boolean,
  category_match     boolean,
  in_stock           boolean,
  stock_price_bdt    integer,
  stock_confirmed_at timestamptz
)
language plpgsql stable set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_types        public.shop_type[];
  v_origin       extensions.geography;
  v_category_id  bigint;
begin
  if p_radius_km is null or p_radius_km not in (1, 3, 5, 10) then
    raise exception 'radius must be 1, 3, 5 or 10 km' using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;

  v_types := coalesce(
    p_types,
    case
      when p_kind is null then null
      when p_kind = 'plant' then array['nursery']::public.shop_type[]
      else array['pet_shop', 'vet_supply']::public.shop_type[]
    end);
  v_origin := extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;

  if p_taxon_id is not null then
    select t.shop_category_id into v_category_id from public.taxa t where t.id = p_taxon_id;
  end if;

  return query
  with candidates as (
    select
      s.*,
      extensions.st_distance(s.location, v_origin)::integer as dist,
      case
        when v_category_id is not null then exists (
          select 1 from public.shop_categories sc
          where sc.shop_id = s.id and sc.category_id = v_category_id)
        when p_kind is not null then exists (
          select 1 from public.shop_categories sc
          join public.catalogue_categories cc on cc.id = sc.category_id
          where sc.shop_id = s.id and p_kind = any (cc.kinds))
        else false
      end as cat_match
    from public.shops s
    where s.status = 'active'
      and (v_types is null or s.shop_type = any (v_types))
      and extensions.st_dwithin(s.location, v_origin, p_radius_km * 1000)
  )
  select
    c.id, c.name_en, c.name_bn, c.shop_type,
    extensions.st_y(c.location::extensions.geometry),
    extensions.st_x(c.location::extensions.geometry),
    c.dist, c.address_en, c.address_bn, c.area, c.phone, c.whatsapp, c.opening_hours,
    public.shop_open_now(c.opening_hours),
    c.rating, c.rating_count, c.verified_at, c.is_partner, c.cat_match,
    stock.confirmed_at is not null,
    stock.price_bdt,
    stock.confirmed_at
  from candidates c
  left join lateral (
    select ps.price_bdt, ps.confirmed_at
    from public.partner_stock ps
    where c.is_partner
      and p_taxon_id is not null
      and ps.shop_id = c.id
      and ps.taxon_id = p_taxon_id
      and ps.in_stock
      and ps.confirmed_at > now() - interval '14 days'
    order by ps.confirmed_at desc
    limit 1
  ) stock on true
  order by (stock.confirmed_at is not null) desc, c.cat_match desc, c.dist asc
  limit least(greatest(coalesce(p_limit, 30), 1), 50);
end $$;

-- "What you'll need": items suited to a taxon or, failing that, to its whole kind.
create or replace function public.accessories_for(
  p_taxon_id bigint default null,
  p_kind     public.taxon_kind default null
)
returns table (
  item_id           bigint,
  category_slug     text,
  category_name_en  text,
  category_name_bn  text,
  category_sort     smallint,
  name_en           text,
  name_bn           text,
  description_en    text,
  description_bn    text,
  price_min_bdt     integer,
  price_max_bdt     integer,
  price_checked_on  date,
  essential         boolean
)
language sql stable set search_path = '' as $$
  with target as (
    select coalesce(p_kind, (select t.kind from public.taxa t where t.id = p_taxon_id)) as kind
  )
  select i.id, c.slug, c.name_en, c.name_bn, c.sort, i.name_en, i.name_bn,
         i.description_en, i.description_bn, i.price_min_bdt, i.price_max_bdt,
         i.price_checked_on, bool_or(s.essential)
  from public.catalogue_item_suits s
  join public.catalogue_items i on i.id = s.item_id and i.is_active
  join public.catalogue_categories c on c.id = i.category_id and c.is_supply
  cross join target
  where (p_taxon_id is not null and s.taxon_id = p_taxon_id)
     or (target.kind is not null and s.kind = target.kind)
  group by i.id, c.slug, c.name_en, c.name_bn, c.sort
  order by bool_or(s.essential) desc, c.sort, i.sort, i.name_en
$$;

-- Find the taxon an engine's answer refers to: exact name first, then a genus-level taxon.
create or replace function public.match_taxon(
  p_kind  public.taxon_kind,
  p_names text[]
)
returns bigint language sql stable set search_path = '' as $$
  with names as (
    select lower(btrim(n)) as n, ord
    from unnest(p_names) with ordinality as u(n, ord)
    where n is not null and btrim(n) <> ''
  )
  select id from (
    select t.id, 1 as pref, names.ord
    from public.taxa t join names on names.n = any (t.match_names)
    where t.kind = p_kind and t.is_active
    union all
    select t.id, 2 as pref, names.ord
    from public.taxa t join names on lower(t.genus) = split_part(names.n, ' ', 1)
    where t.kind = p_kind and t.is_active and t.rank = 'genus'
  ) m
  order by pref, ord
  limit 1
$$;

-- Care card for a taxon, falling back to the kind-level card. Returns tips in display order.
create or replace function public.care_for(p_taxon_id bigint)
returns table (
  care_card_id bigint,
  status       public.content_status,
  is_fallback  boolean,
  topic        public.care_topic,
  body_en      text,
  body_bn      text
)
language sql stable set search_path = '' as $$
  with card as (
    select cc.id, cc.status, false as is_fallback
    from public.care_cards cc where cc.taxon_id = p_taxon_id
    union all
    select cc.id, cc.status, true
    from public.care_cards cc
    join public.taxa t on t.id = p_taxon_id and cc.kind = t.kind
  ),
  chosen as (select * from card order by is_fallback limit 1)
  select chosen.id, chosen.status, chosen.is_fallback, tip.topic, tip.body_en, tip.body_bn
  from chosen join public.care_tips tip on tip.care_card_id = chosen.id
  order by tip.sort, tip.topic
$$;

-- Atomic daily quota. Returns the count after this call, or null when the limit is reached.
create or replace function public.consume_quota(p_subject text, p_limit integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_day   date := (now() at time zone 'Asia/Dhaka')::date;
  v_count integer;
begin
  insert into public.usage_counters as uc (subject, day, count)
  values (p_subject, v_day, 1)
  on conflict (subject, day) do update set count = uc.count + 1
    where uc.count < p_limit
  returning uc.count into v_count;
  return v_count;
end $$;

create or replace function public.log_shop_search(
  p_kind public.taxon_kind, p_taxon_id bigint, p_radius_km integer, p_result_count integer
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;
  insert into public.search_events (user_id, kind, taxon_id, radius_km, result_count)
  values (auth.uid(), p_kind, p_taxon_id, p_radius_km, least(greatest(p_result_count, 0), 32767));
end $$;

create or replace function public.log_shop_contact(p_shop_id uuid, p_action public.contact_action)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;
  insert into public.shop_contact_events (shop_id, user_id, action)
  values (p_shop_id, auth.uid(), p_action);
end $$;

-- Gateway-only: all storage paths a user owns, so account deletion can remove the files.
create or replace function public.user_photo_paths(p_user_id uuid)
returns table (path text) language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o
  where o.bucket_id = 'photos' and o.name like p_user_id::text || '/%'
$$;

-- Admin dashboard: the analytics counts named in the brief, per Dhaka calendar day.
create or replace view public.admin_daily_stats with (security_invoker = true) as
with days as (
  select (i.created_at at time zone 'Asia/Dhaka')::date as day,
         count(*) as identifications,
         count(*) filter (where i.status = 'confident') as confident,
         count(*) filter (where i.status = 'low_confidence') as low_confidence,
         count(*) filter (where i.status in ('not_recognised', 'failed')) as unusable,
         round(avg(i.response_ms)) as avg_response_ms,
         sum(i.cost_usd) as engine_cost_usd
  from public.identifications i group by 1
), searches as (
  select (e.created_at at time zone 'Asia/Dhaka')::date as day, count(*) as shop_searches
  from public.search_events e group by 1
), contacts as (
  select (e.created_at at time zone 'Asia/Dhaka')::date as day,
         count(*) filter (where e.action = 'call') as calls,
         count(*) filter (where e.action = 'whatsapp') as whatsapps,
         count(*) filter (where e.action = 'directions') as directions
  from public.shop_contact_events e group by 1
)
select coalesce(d.day, s.day, c.day) as day,
       coalesce(d.identifications, 0) as identifications,
       coalesce(d.confident, 0) as confident,
       coalesce(d.low_confidence, 0) as low_confidence,
       coalesce(d.unusable, 0) as unusable,
       case when coalesce(d.identifications, 0) = 0 then null
            else round(d.confident::numeric / d.identifications, 3) end as success_rate,
       d.avg_response_ms,
       coalesce(d.engine_cost_usd, 0) as engine_cost_usd,
       coalesce(s.shop_searches, 0) as shop_searches,
       coalesce(c.calls, 0) as calls,
       coalesce(c.whatsapps, 0) as whatsapps,
       coalesce(c.directions, 0) as directions
from days d
full join searches s on s.day = d.day
full join contacts c on c.day = coalesce(d.day, s.day);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.app_admins            enable row level security;
alter table public.profiles              enable row level security;
alter table public.catalogue_categories  enable row level security;
alter table public.taxa                  enable row level security;
alter table public.care_cards            enable row level security;
alter table public.care_tips             enable row level security;
alter table public.catalogue_items       enable row level security;
alter table public.catalogue_item_suits  enable row level security;
alter table public.identifications       enable row level security;
alter table public.identification_matches enable row level security;
alter table public.usage_counters        enable row level security;
alter table public.flags                 enable row level security;
alter table public.collection_items      enable row level security;
alter table public.reminders             enable row level security;
alter table public.shops                 enable row level security;
alter table public.shop_categories       enable row level security;
alter table public.partner_stock         enable row level security;
alter table public.search_events         enable row level security;
alter table public.shop_contact_events   enable row level security;

-- Admins
create policy admins_read on public.app_admins for select using (public.is_admin());

-- Profiles: your own row
create policy profiles_own_read on public.profiles for select using (id = auth.uid());
create policy profiles_own_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- Public reference content: anyone may read; only admins may change
create policy categories_read on public.catalogue_categories for select using (true);
create policy categories_admin on public.catalogue_categories for all
  using (public.is_admin()) with check (public.is_admin());

create policy taxa_read on public.taxa for select using (is_active or public.is_admin());
create policy taxa_admin on public.taxa for all using (public.is_admin()) with check (public.is_admin());

create policy care_cards_read on public.care_cards for select using (true);
create policy care_cards_admin on public.care_cards for all
  using (public.is_admin()) with check (public.is_admin());

create policy care_tips_read on public.care_tips for select using (true);
create policy care_tips_admin on public.care_tips for all
  using (public.is_admin()) with check (public.is_admin());

create policy items_read on public.catalogue_items for select using (is_active or public.is_admin());
create policy items_admin on public.catalogue_items for all
  using (public.is_admin()) with check (public.is_admin());

create policy suits_read on public.catalogue_item_suits for select using (true);
create policy suits_admin on public.catalogue_item_suits for all
  using (public.is_admin()) with check (public.is_admin());

create policy shops_read on public.shops for select using (status = 'active' or public.is_admin());
create policy shops_admin on public.shops for all using (public.is_admin()) with check (public.is_admin());

create policy shop_categories_read on public.shop_categories for select using (true);
create policy shop_categories_admin on public.shop_categories for all
  using (public.is_admin()) with check (public.is_admin());

create policy partner_stock_read on public.partner_stock for select using (true);
create policy partner_stock_admin on public.partner_stock for all
  using (public.is_admin()) with check (public.is_admin());

-- Identifications: written by the gateway (service role); people read their own
create policy identifications_own_read on public.identifications for select
  using (user_id = auth.uid() or public.is_admin());
create policy matches_own_read on public.identification_matches for select
  using (exists (select 1 from public.identifications i
                 where i.id = identification_id and (i.user_id = auth.uid() or public.is_admin())));

-- Flags: report your own identifications; admins triage
create policy flags_own_read on public.flags for select using (user_id = auth.uid() or public.is_admin());
create policy flags_own_insert on public.flags for insert
  with check (user_id = auth.uid()
              and status = 'open'
              and exists (select 1 from public.identifications i
                          where i.id = identification_id and i.user_id = auth.uid()));
create policy flags_admin_update on public.flags for update
  using (public.is_admin()) with check (public.is_admin());

-- My Collection: registered (phone-verified) users only, own rows only
create policy collection_own_read on public.collection_items for select using (user_id = auth.uid());
create policy collection_own_insert on public.collection_items for insert
  with check (user_id = auth.uid() and public.is_registered());
create policy collection_own_update on public.collection_items for update
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_registered());
create policy collection_own_delete on public.collection_items for delete using (user_id = auth.uid());

create policy reminders_own_read on public.reminders for select using (user_id = auth.uid());
create policy reminders_own_insert on public.reminders for insert
  with check (user_id = auth.uid() and public.is_registered()
              and exists (select 1 from public.collection_items c
                          where c.id = collection_item_id and c.user_id = auth.uid()));
create policy reminders_own_update on public.reminders for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
              and exists (select 1 from public.collection_items c
                          where c.id = collection_item_id and c.user_id = auth.uid()));
create policy reminders_own_delete on public.reminders for delete using (user_id = auth.uid());

-- Events: written through the log_* functions; admins read
create policy search_events_admin on public.search_events for select using (public.is_admin());
create policy contact_events_admin on public.shop_contact_events for select using (public.is_admin());

-- usage_counters: no policies, so only the service role (gateway) can touch it.

-- ---------------------------------------------------------------------------
-- Function privileges: gateway-only functions are closed to app users
-- ---------------------------------------------------------------------------
revoke execute on function public.consume_quota(text, integer) from public, anon, authenticated;
revoke execute on function public.user_photo_paths(uuid) from public, anon, authenticated;
grant execute on function public.consume_quota(text, integer) to service_role;
grant execute on function public.user_photo_paths(uuid) to service_role;

revoke execute on function public.log_shop_search(public.taxon_kind, bigint, integer, integer) from public, anon;
revoke execute on function public.log_shop_contact(uuid, public.contact_action) from public, anon;
grant execute on function public.log_shop_search(public.taxon_kind, bigint, integer, integer) to authenticated;
grant execute on function public.log_shop_contact(uuid, public.contact_action) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: one private bucket. Layout:
--   <user id>/ident/<identification id>.jpg     temporary, written by the gateway, purged after 24 h
--   <user id>/collection/<collection item>.jpg  kept until the user deletes it or the account
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy photos_own_read on storage.objects for select
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy photos_collection_insert on storage.objects for insert
  with check (bucket_id = 'photos'
              and (storage.foldername(name))[1] = auth.uid()::text
              and (storage.foldername(name))[2] = 'collection'
              and public.is_registered());
create policy photos_collection_update on storage.objects for update
  using (bucket_id = 'photos'
         and (storage.foldername(name))[1] = auth.uid()::text
         and (storage.foldername(name))[2] = 'collection');
create policy photos_own_delete on storage.objects for delete
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
