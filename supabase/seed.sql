-- LOCAL DEVELOPMENT ONLY. Supabase loads this file on `supabase db reset`, never in production.
-- Fictional demo shops around GEC Circle, Chattogram, so the shop screens have data before
-- the field survey. All are marked is_demo = true and use placeholder numbers.

insert into public.shops (id, name_en, name_bn, shop_type, location, address_en, area, city,
                          phone, whatsapp, opening_hours, rating, rating_count, verified_at,
                          consent_at, is_partner, is_demo)
values
  ('00000000-0000-4000-8000-000000000001', 'Demo Green Nursery', 'ডেমো গ্রিন নার্সারি', 'nursery',
   'SRID=4326;POINT(91.8215 22.3596)', 'Demo address 1', 'GEC', 'Chattogram',
   '+8801700000001', '+8801700000001',
   '{"sat":[["09:00","21:00"]],"sun":[["09:00","21:00"]],"mon":[["09:00","21:00"]],"tue":[["09:00","21:00"]],"wed":[["09:00","21:00"]],"thu":[["09:00","21:00"]],"fri":[["15:00","21:00"]]}',
   4.5, 12, now(), now(), true, true),
  ('00000000-0000-4000-8000-000000000002', 'Demo Orchid House', 'ডেমো অর্কিড হাউস', 'nursery',
   'SRID=4326;POINT(91.8300 22.3650)', 'Demo address 2', 'Nasirabad', 'Chattogram',
   '+8801700000002', null,
   '{"sat":[["10:00","20:00"]],"sun":[["10:00","20:00"]],"mon":[["10:00","20:00"]],"tue":[["10:00","20:00"]],"wed":[["10:00","20:00"]],"thu":[["10:00","20:00"]]}',
   null, 0, now(), now(), false, true),
  ('00000000-0000-4000-8000-000000000003', 'Demo Fruit Sapling Centre', 'ডেমো ফলের চারা কেন্দ্র', 'nursery',
   'SRID=4326;POINT(91.8000 22.3400)', 'Demo address 3', 'Agrabad', 'Chattogram',
   '+8801700000003', '+8801700000003', null, null, 0, now(), now(), false, true),
  ('00000000-0000-4000-8000-000000000004', 'Demo Pet Corner', 'ডেমো পেট কর্নার', 'pet_shop',
   'SRID=4326;POINT(91.8230 22.3580)', 'Demo address 4', 'GEC', 'Chattogram',
   '+8801700000004', '+8801700000004',
   '{"sat":[["10:00","22:00"]],"sun":[["10:00","22:00"]],"mon":[["10:00","22:00"]],"tue":[["10:00","22:00"]],"wed":[["10:00","22:00"]],"thu":[["10:00","22:00"]],"fri":[["16:00","22:00"]]}',
   4.2, 30, now(), now(), false, true),
  ('00000000-0000-4000-8000-000000000005', 'Demo Bird and Aquarium', 'ডেমো পাখি ও অ্যাকোয়ারিয়াম', 'pet_shop',
   'SRID=4326;POINT(91.8350 22.3700)', 'Demo address 5', 'Muradpur', 'Chattogram',
   '+8801700000005', '+8801700000005', null, null, 0, now(), now(), false, true),
  ('00000000-0000-4000-8000-000000000006', 'Demo Vet Supplies', 'ডেমো ভেট সাপ্লাইজ', 'vet_supply',
   'SRID=4326;POINT(91.8180 22.3550)', 'Demo address 6', 'Lalkhan Bazar', 'Chattogram',
   '+8801700000006', null, null, null, 0, now(), now(), false, true),
  ('00000000-0000-4000-8000-000000000007', 'Demo Animal Clinic', 'ডেমো পশু ক্লিনিক', 'vet_clinic',
   'SRID=4326;POINT(91.8250 22.3620)', 'Demo address 7', 'GEC', 'Chattogram',
   '+8801700000007', '+8801700000007',
   '{"sat":[["09:00","13:00"],["17:00","21:00"]],"sun":[["09:00","13:00"],["17:00","21:00"]],"mon":[["09:00","13:00"],["17:00","21:00"]],"tue":[["09:00","13:00"],["17:00","21:00"]],"wed":[["09:00","13:00"],["17:00","21:00"]],"thu":[["09:00","13:00"],["17:00","21:00"]]}',
   null, 0, now(), now(), false, true);

insert into public.shop_categories (shop_id, category_id)
select v.shop_id::uuid, c.id
from (values
  ('00000000-0000-4000-8000-000000000001', 'indoor_foliage'),
  ('00000000-0000-4000-8000-000000000001', 'flowering_plants'),
  ('00000000-0000-4000-8000-000000000001', 'herbs'),
  ('00000000-0000-4000-8000-000000000001', 'pots'),
  ('00000000-0000-4000-8000-000000000001', 'potting_mix'),
  ('00000000-0000-4000-8000-000000000001', 'fertiliser'),
  ('00000000-0000-4000-8000-000000000002', 'orchids'),
  ('00000000-0000-4000-8000-000000000002', 'potting_mix'),
  ('00000000-0000-4000-8000-000000000003', 'fruit_saplings'),
  ('00000000-0000-4000-8000-000000000003', 'fertiliser'),
  ('00000000-0000-4000-8000-000000000004', 'cat_food'),
  ('00000000-0000-4000-8000-000000000004', 'dog_food'),
  ('00000000-0000-4000-8000-000000000004', 'litter'),
  ('00000000-0000-4000-8000-000000000004', 'toys'),
  ('00000000-0000-4000-8000-000000000004', 'bowls'),
  ('00000000-0000-4000-8000-000000000005', 'bird_food'),
  ('00000000-0000-4000-8000-000000000005', 'cages'),
  ('00000000-0000-4000-8000-000000000006', 'grooming'),
  ('00000000-0000-4000-8000-000000000006', 'cat_food'),
  ('00000000-0000-4000-8000-000000000006', 'dog_food')
) as v(shop_id, slug)
join public.catalogue_categories c on c.slug = v.slug;

-- One partner stock line so the "Has this in stock" badge can be tested.
insert into public.partner_stock (shop_id, taxon_id, price_bdt, in_stock, confirmed_at)
select '00000000-0000-4000-8000-000000000001', t.id, 250, true, now() - interval '2 days'
from public.taxa t where t.key = 'money_plant';
