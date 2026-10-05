begin;
select plan(28);

-- Schema --------------------------------------------------------------------
select has_table('public', t, 'table ' || t || ' exists')
from unnest(array['profiles', 'taxa', 'care_cards', 'care_tips', 'identifications',
                  'identification_matches', 'collection_items', 'reminders', 'shops',
                  'shop_categories', 'catalogue_categories', 'catalogue_items',
                  'catalogue_item_suits', 'flags', 'partner_stock']) as t;

-- Taxon matching --------------------------------------------------------------
select is(match_taxon('plant', array['Scindapsus aureus']),
          (select id from taxa where key = 'money_plant'),
          'a synonym finds money plant');
select is(match_taxon('plant', array['AGLAONEMA pictum']),
          (select id from taxa where key = 'aglaonema'),
          'an unlisted Aglaonema species falls back to the genus taxon, case-insensitively');
select is(match_taxon('plant', array['Ficus elastica']), null, 'an unknown plant has no taxon');
select is(match_taxon('cat', array['Epipremnum aureum']), null, 'matching respects the kind');
select is(match_taxon('dog', array['Mixed breed dog', 'German Shepherd']),
          (select id from taxa where key = 'dog_local'),
          'the first name in the list wins');

-- Care cards ------------------------------------------------------------------
select ok((select bool_and(not is_fallback) from care_for((select id from taxa where key = 'money_plant'))),
          'money plant uses its own care card');
select ok((select bool_and(is_fallback) and count(*) = 4 from care_for((select id from taxa where key = 'cat_persian'))),
          'a breed without its own card falls back to the cat card');

-- Accessories -----------------------------------------------------------------
select ok(exists (select 1 from accessories_for((select id from taxa where key = 'snake_plant'))
                  where name_en = 'Cactus and succulent mix' and essential),
          'snake plant gets cactus mix as essential');
select ok(not exists (select 1 from accessories_for((select id from taxa where key = 'snake_plant')) a
                      join catalogue_categories c on c.slug = a.category_slug where not c.is_supply),
          'live-plant categories never appear as accessories');
select ok((select essential from accessories_for((select id from taxa where key = 'cat_persian'))
           where name_en = 'Grooming brush'),
          'a taxon-specific essential flag overrides the kind-wide optional flag');

-- Opening hours -----------------------------------------------------------------
select is(shop_open_now('{"sat":[["09:00","21:00"]]}', '2026-10-03 10:00+06'), true, 'open on Saturday morning');
select is(shop_open_now('{"sat":[["09:00","21:00"]]}', '2026-10-02 10:00+06'), false, 'closed on a day not listed');
select is(shop_open_now('{"sat":[["22:00","02:00"]]}', '2026-10-04 01:00+06'), true, 'overnight slot spills into Sunday');

select * from finish();
rollback;
