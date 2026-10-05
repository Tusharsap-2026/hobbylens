begin;
select plan(9);

-- Demo shops from seed.sql, searched from GEC Circle, Chattogram.
\set lat 22.3596
\set lng 91.8215

select is((select name_en from nearby_shops(:lat, :lng, 1, 'plant', (select id from taxa where key = 'money_plant')) limit 1),
          'Demo Green Nursery', 'the partner nursery is first for money plant');
select ok((select in_stock and stock_price_bdt = 250
           from nearby_shops(:lat, :lng, 1, 'plant', (select id from taxa where key = 'money_plant')) limit 1),
          'fresh partner stock shows the badge and price');

select is((select name_en from nearby_shops(:lat, :lng, 3, 'plant', (select id from taxa where key = 'phalaenopsis')) limit 1),
          'Demo Orchid House', 'a nursery stocking orchids outranks a closer one that does not');

select is((select count(*)::int from nearby_shops(:lat, :lng, 3, 'plant')), 2, '3 km finds two nurseries');
select is((select count(*)::int from nearby_shops(:lat, :lng, 5, 'plant')), 3, '5 km adds the third');

select ok((select bool_and(shop_type in ('pet_shop', 'vet_supply')) from nearby_shops(:lat, :lng, 5, 'dog')),
          'pets search pet shops and vet supply stores only');
select is((select name_en from nearby_shops(:lat, :lng, 3, null, null, array['vet_clinic']::shop_type[])),
          'Demo Animal Clinic', 'vet clinics are found by type');

update partner_stock set confirmed_at = now() - interval '15 days';
select ok(not (select in_stock from nearby_shops(:lat, :lng, 1, 'plant', (select id from taxa where key = 'money_plant')) limit 1),
          'stock confirmed more than 14 days ago no longer shows the badge');

select throws_ok($$ select * from nearby_shops(22.3, 91.8, 2) $$, '22023', 'radius must be 1, 3, 5 or 10 km',
                 'only the four radius options are accepted');

select * from finish();
rollback;
