-- HobbyLens: starter reference content.
--
-- STATUS: DRAFT. Every care card below is status 'draft' and must be reviewed by the
-- horticulturist (plants) or the vet (animals) in the admin panel before launch. The app
-- labels draft cards as unreviewed. Pet-safety values follow the ASPCA toxic/non-toxic
-- plant lists where known; anything not confirmed is 'unknown'.
--
-- Catalogue prices are deliberately NULL: they are to be filled from the shop survey.
-- The app shows "ask the shop for the price" until they are.

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------
insert into public.catalogue_categories (slug, name_en, name_bn, kinds, is_supply, sort) values
  -- Live plants (used to match nurseries; not shown as accessories)
  ('indoor_foliage',   'Indoor foliage plants', 'ইনডোর পাতাবাহার গাছ', '{plant}', false, 10),
  ('flowering_plants', 'Flowering plants',      'ফুলের গাছ',            '{plant}', false, 11),
  ('fruit_saplings',   'Fruit saplings',        'ফলের চারা',            '{plant}', false, 12),
  ('herbs',            'Herbs',                 'ভেষজ গাছ',             '{plant}', false, 13),
  ('orchids',          'Orchids',               'অর্কিড',               '{plant}', false, 14),
  -- Plant supplies
  ('pots',             'Pots and planters',     'টব',                   '{plant}', true, 20),
  ('potting_mix',      'Soil and potting mix',  'মাটি ও পটিং মিক্স',     '{plant}', true, 21),
  ('fertiliser',       'Fertiliser',            'সার',                  '{plant}', true, 22),
  ('plant_tools',      'Garden tools',          'বাগানের সরঞ্জাম',       '{plant}', true, 23),
  -- Pet supplies
  ('cat_food',         'Cat food',              'বিড়ালের খাবার',         '{cat}', true, 30),
  ('litter',           'Litter and litter boxes', 'লিটার ও লিটার বক্স',   '{cat}', true, 31),
  ('dog_food',         'Dog food',              'কুকুরের খাবার',         '{dog}', true, 32),
  ('collars_leashes',  'Collars and leashes',   'কলার ও লিশ',            '{dog}', true, 33),
  ('bird_food',        'Bird food',             'পাখির খাবার',           '{bird}', true, 34),
  ('cages',            'Cages',                 'খাঁচা',                 '{bird}', true, 35),
  ('bowls',            'Bowls and feeders',     'খাবারের পাত্র',          '{cat,dog,bird}', true, 40),
  ('beds_carriers',    'Beds and carriers',     'বিছানা ও ক্যারিয়ার',     '{cat,dog}', true, 41),
  ('grooming',         'Grooming',              'গ্রুমিং সামগ্রী',         '{cat,dog}', true, 42),
  ('toys',             'Toys',                  'খেলনা',                 '{cat,dog,bird}', true, 43);

-- ---------------------------------------------------------------------------
-- Species, genera and breeds
-- ---------------------------------------------------------------------------
insert into public.taxa (key, kind, rank, scientific_name, name_en, name_bn, genus, family,
                         match_names, pet_safety, shop_category_id)
select v.key, v.kind::public.taxon_kind, v.rank, v.scientific_name, v.name_en, v.name_bn, v.genus,
       v.family, v.match_names, v.pet_safety::public.pet_safety, c.id
from (values
  ('money_plant', 'plant', 'species', 'Epipremnum aureum', 'Money plant (golden pothos)', 'মানি প্ল্যান্ট',
   'Epipremnum', 'Araceae',
   array['epipremnum aureum', 'scindapsus aureus', 'pothos aureus', 'golden pothos', 'money plant', 'devil''s ivy', 'pothos'],
   'toxic_both', 'indoor_foliage'),
  ('snake_plant', 'plant', 'species', 'Dracaena trifasciata', 'Snake plant', 'স্নেক প্ল্যান্ট',
   'Dracaena', 'Asparagaceae',
   array['dracaena trifasciata', 'sansevieria trifasciata', 'snake plant', 'mother-in-law''s tongue'],
   'toxic_both', 'indoor_foliage'),
  ('aglaonema', 'plant', 'genus', 'Aglaonema', 'Aglaonema (Chinese evergreen)', 'অ্যাগলোনেমা',
   'Aglaonema', 'Araceae',
   array['aglaonema', 'aglaonema commutatum', 'aglaonema modestum', 'aglaonema crispum', 'chinese evergreen'],
   'toxic_both', 'indoor_foliage'),
  ('rose', 'plant', 'genus', 'Rosa', 'Rose', 'গোলাপ',
   'Rosa', 'Rosaceae',
   array['rosa', 'rosa × hybrida', 'rosa x hybrida', 'rosa hybrida', 'rosa chinensis', 'rose', 'garden rose'],
   'safe', 'flowering_plants'),
  ('tulsi', 'plant', 'species', 'Ocimum tenuiflorum', 'Tulsi (holy basil)', 'তুলসী',
   'Ocimum', 'Lamiaceae',
   array['ocimum tenuiflorum', 'ocimum sanctum', 'holy basil', 'tulsi', 'tulasi'],
   'unknown', 'herbs'),
  ('mango', 'plant', 'species', 'Mangifera indica', 'Mango', 'আম',
   'Mangifera', 'Anacardiaceae',
   array['mangifera indica', 'mango'],
   'unknown', 'fruit_saplings'),
  ('phalaenopsis', 'plant', 'genus', 'Phalaenopsis', 'Moth orchid (Phalaenopsis)', 'মথ অর্কিড (ফ্যালেনোপসিস)',
   'Phalaenopsis', 'Orchidaceae',
   array['phalaenopsis', 'phalaenopsis amabilis', 'phalaenopsis aphrodite', 'moth orchid'],
   'safe', 'orchids'),
  ('dendrobium', 'plant', 'genus', 'Dendrobium', 'Dendrobium orchid', 'ডেনড্রোবিয়াম অর্কিড',
   'Dendrobium', 'Orchidaceae',
   array['dendrobium', 'dendrobium nobile', 'dendrobium bigibbum', 'dendrobium orchid'],
   'unknown', 'orchids'),

  ('cat_local', 'cat', 'landrace', 'Felis catus', 'Domestic cat (local or mixed breed)', 'দেশি বিড়াল',
   'Felis', 'Felidae',
   array['felis catus', 'domestic cat', 'domestic shorthair', 'domestic short-haired cat', 'mixed breed cat', 'local cat', 'cat'],
   null, null),
  ('cat_persian', 'cat', 'breed', 'Felis catus', 'Persian cat', 'পারস্য বিড়াল',
   'Felis', 'Felidae', array['persian', 'persian cat'], null, null),
  ('cat_siamese', 'cat', 'breed', 'Felis catus', 'Siamese cat', 'সিয়ামিজ বিড়াল',
   'Felis', 'Felidae', array['siamese', 'siamese cat'], null, null),

  ('dog_local', 'dog', 'landrace', 'Canis familiaris', 'Domestic dog (local or mixed breed)', 'দেশি কুকুর',
   'Canis', 'Canidae',
   array['canis familiaris', 'canis lupus familiaris', 'mixed breed dog', 'local dog', 'indian pariah dog', 'dog'],
   null, null),
  ('dog_german_shepherd', 'dog', 'breed', 'Canis familiaris', 'German Shepherd', 'জার্মান শেফার্ড',
   'Canis', 'Canidae', array['german shepherd', 'german shepherd dog', 'alsatian'], null, null),
  ('dog_labrador', 'dog', 'breed', 'Canis familiaris', 'Labrador Retriever', 'ল্যাব্রাডর রিট্রিভার',
   'Canis', 'Canidae', array['labrador retriever', 'labrador'], null, null),

  ('budgerigar', 'bird', 'species', 'Melopsittacus undulatus', 'Budgerigar', 'বাজরিগার',
   'Melopsittacus', 'Psittaculidae', array['melopsittacus undulatus', 'budgerigar', 'budgie'], null, null),
  ('lovebird', 'bird', 'genus', 'Agapornis', 'Lovebird', 'লাভবার্ড',
   'Agapornis', 'Psittaculidae', array['agapornis', 'agapornis roseicollis', 'agapornis fischeri', 'lovebird'], null, null),
  ('cockatiel', 'bird', 'species', 'Nymphicus hollandicus', 'Cockatiel', 'ককাটিয়েল',
   'Nymphicus', 'Cacatuidae', array['nymphicus hollandicus', 'cockatiel'], null, null),
  ('pigeon', 'bird', 'species', 'Columba livia domestica', 'Domestic pigeon', 'কবুতর',
   'Columba', 'Columbidae', array['columba livia domestica', 'columba livia', 'domestic pigeon', 'pigeon', 'rock dove'], null, null)
) as v(key, kind, rank, scientific_name, name_en, name_bn, genus, family, match_names, pet_safety, shop_category)
left join public.catalogue_categories c on c.slug = v.shop_category;

-- ---------------------------------------------------------------------------
-- Care cards (DRAFT - pending expert review)
-- ---------------------------------------------------------------------------
insert into public.care_cards (taxon_id, status)
select id, 'draft' from public.taxa
where key in ('money_plant', 'snake_plant', 'aglaonema', 'rose', 'tulsi', 'mango', 'phalaenopsis', 'dendrobium');

insert into public.care_cards (kind, status) values ('cat', 'draft'), ('dog', 'draft'), ('bird', 'draft');

insert into public.care_tips (care_card_id, topic, body_en, body_bn, sort)
select cc.id, v.topic::public.care_topic, v.body_en, v.body_bn, v.sort
from (values
  ('money_plant', 'light', 'Bright, indirect light. Copes with low light but grows slowly; keep it out of harsh afternoon sun.',
   'উজ্জ্বল কিন্তু পরোক্ষ আলো। কম আলোতেও টিকে থাকে, তবে ধীরে বাড়ে; দুপুরের কড়া রোদ থেকে দূরে রাখুন।', 1),
  ('money_plant', 'water', 'Water when the top 2–3 cm of soil is dry. Do not let the pot stand in water.',
   'মাটির ওপরের ২–৩ সেমি শুকিয়ে গেলে পানি দিন। টবের নিচে পানি জমে থাকতে দেবেন না।', 2),
  ('money_plant', 'soil', 'Loose, well-draining potting mix. Cuttings also grow in a jar of clean water.',
   'ঝুরঝুরে, সহজে পানি নিষ্কাশন হয় এমন মাটি। ডাল কেটে পরিষ্কার পানির বোতলেও জন্মানো যায়।', 3),

  ('snake_plant', 'light', 'Bright, indirect light is best; it also copes with low light.',
   'পরোক্ষ উজ্জ্বল আলো সবচেয়ে ভালো; কম আলোতেও মানিয়ে নেয়।', 1),
  ('snake_plant', 'water', 'Water only when the soil is completely dry, roughly every 2–3 weeks and less in winter. Overwatering rots the roots.',
   'মাটি পুরো শুকিয়ে গেলে তবেই পানি দিন, সাধারণত ২–৩ সপ্তাহে একবার, শীতে আরও কম। বেশি পানিতে শিকড় পচে যায়।', 2),
  ('snake_plant', 'soil', 'Sandy, fast-draining mix such as cactus mix, in a pot with a drainage hole.',
   'বালুমিশ্রিত, দ্রুত পানি নিষ্কাশন হয় এমন মাটি, যেমন ক্যাকটাস মিক্স; টবের নিচে ছিদ্র থাকতে হবে।', 3),

  ('aglaonema', 'light', 'Medium to bright indirect light; no direct sun on the leaves.',
   'মাঝারি থেকে উজ্জ্বল পরোক্ষ আলো; পাতায় সরাসরি রোদ লাগাবেন না।', 1),
  ('aglaonema', 'water', 'Keep the soil lightly moist; water when the top 2–3 cm is dry.',
   'মাটি হালকা ভেজা রাখুন; ওপরের ২–৩ সেমি শুকালে পানি দিন।', 2),
  ('aglaonema', 'soil', 'Well-draining potting mix rich in organic matter.',
   'জৈব উপাদানসমৃদ্ধ, পানি নিষ্কাশন হয় এমন মাটি।', 3),
  ('aglaonema', 'temperature', 'Dislikes cold; keep it away from air-conditioner vents.',
   'ঠান্ডা সহ্য করতে পারে না; এসির বাতাস থেকে দূরে রাখুন।', 4),

  ('rose', 'light', 'At least 6 hours of direct sun a day.',
   'দিনে অন্তত ৬ ঘণ্টা সরাসরি রোদ।', 1),
  ('rose', 'water', 'Water deeply at the base when the topsoil is dry; keep the leaves dry.',
   'ওপরের মাটি শুকালে গোড়ায় ভালোভাবে পানি দিন; পাতা শুকনো রাখুন।', 2),
  ('rose', 'soil', 'Rich, well-drained soil mixed with compost.',
   'কম্পোস্ট মেশানো উর্বর, পানি নিষ্কাশন হয় এমন মাটি।', 3),
  ('rose', 'fertiliser', 'Feed during the growing season and cut off faded flowers.',
   'বাড়ন্ত মৌসুমে সার দিন এবং শুকনো ফুল ছেঁটে ফেলুন।', 4),

  ('tulsi', 'light', 'Full sun to light shade, with at least 4–6 hours of sun.',
   'পূর্ণ রোদ থেকে হালকা ছায়া; অন্তত ৪–৬ ঘণ্টা রোদ।', 1),
  ('tulsi', 'water', 'Water when the topsoil is dry; do not let water stand.',
   'ওপরের মাটি শুকালে পানি দিন; পানি জমতে দেবেন না।', 2),
  ('tulsi', 'soil', 'Well-drained loamy soil.',
   'পানি নিষ্কাশন হয় এমন দোআঁশ মাটি।', 3),

  ('mango', 'light', 'Full sun.', 'পূর্ণ রোদ।', 1),
  ('mango', 'water', 'Water young saplings regularly, letting the topsoil dry between waterings.',
   'চারা অবস্থায় নিয়মিত পানি দিন, তবে দুবারের মাঝে ওপরের মাটি শুকাতে দিন।', 2),
  ('mango', 'soil', 'Deep, well-drained soil. In a pot, use a large and deep container.',
   'গভীর, পানি নিষ্কাশন হয় এমন মাটি। টবে লাগালে বড় ও গভীর টব ব্যবহার করুন।', 3),

  ('phalaenopsis', 'light', 'Bright, indirect light such as an east-facing window; no direct midday sun.',
   'পরোক্ষ উজ্জ্বল আলো, যেমন পূর্বমুখী জানালা; দুপুরের সরাসরি রোদ নয়।', 1),
  ('phalaenopsis', 'water', 'Water about once a week when the bark mix is nearly dry, then let it drain fully.',
   'ছাল-মিশ্রণ প্রায় শুকিয়ে এলে মোটামুটি সপ্তাহে একবার পানি দিন, তারপর অতিরিক্ত পানি পুরো ঝরিয়ে ফেলুন।', 2),
  ('phalaenopsis', 'soil', 'Orchid bark or coconut husk chips, not garden soil.',
   'অর্কিডের ছাল বা নারকেলের ছোবড়ার টুকরো, সাধারণ মাটি নয়।', 3),

  ('dendrobium', 'light', 'Bright light with some direct morning sun.',
   'উজ্জ্বল আলো, সঙ্গে সকালের কিছুটা সরাসরি রোদ।', 1),
  ('dendrobium', 'water', 'Water when the potting medium is almost dry; more in the growing season, less in winter.',
   'মাধ্যম প্রায় শুকালে পানি দিন; বাড়ন্ত মৌসুমে বেশি, শীতে কম।', 2),
  ('dendrobium', 'soil', 'Coarse bark, charcoal or coconut husk chips that let air reach the roots.',
   'মোটা ছাল, কাঠকয়লা বা নারকেলের ছোবড়ার টুকরো, যাতে শিকড়ে বাতাস পৌঁছায়।', 3)
) as v(taxon_key, topic, body_en, body_bn, sort)
join public.taxa t on t.key = v.taxon_key
join public.care_cards cc on cc.taxon_id = t.id;

insert into public.care_tips (care_card_id, topic, body_en, body_bn, sort)
select cc.id, v.topic::public.care_topic, v.body_en, v.body_bn, v.sort
from (values
  ('cat', 'food', 'Feed a complete cat food; cats need animal protein. Keep clean water out at all times.',
   'পূর্ণাঙ্গ বিড়ালের খাবার দিন; বিড়ালের প্রাণিজ প্রোটিন দরকার। সবসময় পরিষ্কার পানি রাখুন।', 1),
  ('cat', 'space', 'A clean litter box, a scratching post and a quiet place to hide.',
   'পরিষ্কার লিটার বক্স, আঁচড়ানোর খুঁটি এবং লুকানোর মতো নিরিবিলি জায়গা।', 2),
  ('cat', 'grooming', 'Brush weekly; long-haired cats such as Persians need brushing every day.',
   'সপ্তাহে একবার আঁচড়ে দিন; পারস্য বিড়ালের মতো লম্বা লোমের বিড়ালকে প্রতিদিন।', 3),
  ('cat', 'vaccination', 'Ask a vet for a vaccination and deworming schedule.',
   'টিকা ও কৃমিনাশকের সময়সূচি পশু চিকিৎসকের কাছ থেকে জেনে নিন।', 4),

  ('dog', 'food', 'Complete dog food in measured meals and clean water at all times. Chocolate, grapes and onions are toxic to dogs.',
   'মেপে পূর্ণাঙ্গ কুকুরের খাবার দিন, সবসময় পরিষ্কার পানি রাখুন। চকলেট, আঙুর ও পেঁয়াজ কুকুরের জন্য বিষাক্ত।', 1),
  ('dog', 'exercise', 'Daily walks and play; larger breeds need more.',
   'প্রতিদিন হাঁটা ও খেলা; বড় জাতের কুকুরের আরও বেশি দরকার।', 2),
  ('dog', 'grooming', 'Brush regularly and check ears, nails and skin for ticks.',
   'নিয়মিত আঁচড়ান এবং কান, নখ ও চামড়ায় এঁটুলি আছে কি না দেখুন।', 3),
  ('dog', 'vaccination', 'Rabies vaccination, and a vet''s schedule for other vaccines and deworming.',
   'জলাতঙ্কের টিকা, এবং অন্যান্য টিকা ও কৃমিনাশকের জন্য পশু চিকিৎসকের দেওয়া সময়সূচি।', 4),

  ('bird', 'food', 'A seed or pellet mix suited to the species, plus fresh greens; clean water every day.',
   'প্রজাতি অনুযায়ী দানা বা পেলেট মিশ্রণ, সঙ্গে তাজা শাকসবজি; প্রতিদিন পরিষ্কার পানি।', 1),
  ('bird', 'space', 'A cage wide enough to fly between perches, out of direct sun and draughts.',
   'দাঁড়ের এক পাশ থেকে আরেক পাশে উড়তে পারে এমন চওড়া খাঁচা; সরাসরি রোদ ও দমকা বাতাস থেকে দূরে।', 2),
  ('bird', 'grooming', 'Clean the cage tray every few days and offer a shallow dish of water for bathing.',
   'কয়েক দিন পরপর খাঁচার ট্রে পরিষ্কার করুন এবং গোসলের জন্য অগভীর পানির পাত্র দিন।', 3)
) as v(kind, topic, body_en, body_bn, sort)
join public.care_cards cc on cc.kind = v.kind::public.taxon_kind;

-- ---------------------------------------------------------------------------
-- Accessory catalogue (prices to be filled from the shop survey)
-- ---------------------------------------------------------------------------
insert into public.catalogue_items (category_id, name_en, name_bn, sort)
select c.id, v.name_en, v.name_bn, v.sort
from (values
  ('pots',        'Pot with a drainage hole',        'নিচে ছিদ্রযুক্ত টব', 1),
  ('potting_mix', 'Well-draining potting mix',       'ঝুরঝুরে পটিং মিক্স', 1),
  ('potting_mix', 'Cactus and succulent mix',        'ক্যাকটাস ও সাকুলেন্ট মিক্স', 2),
  ('potting_mix', 'Orchid bark mix',                 'অর্কিডের ছাল-মিশ্রণ', 3),
  ('fertiliser',  'Organic compost',                 'জৈব কম্পোস্ট', 1),
  ('fertiliser',  'Fertiliser for flowering plants', 'ফুল গাছের সার', 2),
  ('plant_tools', 'Watering can',                    'ঝাঁঝরি', 1),
  ('plant_tools', 'Moss pole for climbing plants',   'লতানো গাছের জন্য মস পোল', 2),
  ('plant_tools', 'Pruning secateurs',               'ডাল ছাঁটার কাঁচি', 3),

  ('cat_food',    'Dry cat food',                    'বিড়ালের শুকনো খাবার', 1),
  ('litter',      'Cat litter',                      'বিড়ালের লিটার', 1),
  ('litter',      'Litter box',                      'লিটার বক্স', 2),
  ('toys',        'Scratching post',                 'আঁচড়ানোর খুঁটি', 1),
  ('beds_carriers', 'Pet carrier',                   'পোষা প্রাণীর ক্যারিয়ার', 1),
  ('grooming',    'Grooming brush',                  'লোম আঁচড়ানোর ব্রাশ', 1),
  ('bowls',       'Food and water bowls',            'খাবার ও পানির পাত্র', 1),

  ('dog_food',    'Dry dog food',                    'কুকুরের শুকনো খাবার', 1),
  ('collars_leashes', 'Collar and leash',            'কলার ও লিশ', 1),
  ('toys',        'Chew toy',                        'চিবানোর খেলনা', 2),
  ('beds_carriers', 'Dog bed',                       'কুকুরের বিছানা', 2),

  ('cages',       'Bird cage',                       'পাখির খাঁচা', 1),
  ('bird_food',   'Seed mix',                        'দানা মিশ্রণ', 1),
  ('bird_food',   'Cuttlebone (calcium)',            'কাটলবোন (ক্যালসিয়াম)', 2),
  ('toys',        'Perches and swings',              'দাঁড় ও দোলনা', 3),
  ('bowls',       'Seed feeder and water dispenser', 'দানার পাত্র ও পানির ডিসপেনসার', 2)
) as v(category, name_en, name_bn, sort)
join public.catalogue_categories c on c.slug = v.category;

-- Which plants or animals each item suits (kind-wide or one taxon) and whether it is essential.
insert into public.catalogue_item_suits (item_id, kind, taxon_id, essential)
select i.id, v.kind::public.taxon_kind, t.id, v.essential
from (values
  ('Pot with a drainage hole',        'plant', null,           true),
  ('Well-draining potting mix',       'plant', null,           true),
  ('Organic compost',                 'plant', null,           false),
  ('Watering can',                    'plant', null,           false),
  ('Pruning secateurs',               'plant', null,           false),
  ('Cactus and succulent mix',        null,    'snake_plant',  true),
  ('Orchid bark mix',                 null,    'phalaenopsis', true),
  ('Orchid bark mix',                 null,    'dendrobium',   true),
  ('Moss pole for climbing plants',   null,    'money_plant',  false),
  ('Fertiliser for flowering plants', null,    'rose',         true),
  ('Pruning secateurs',               null,    'rose',         true),

  ('Dry cat food',                    'cat',   null,           true),
  ('Cat litter',                      'cat',   null,           true),
  ('Litter box',                      'cat',   null,           true),
  ('Food and water bowls',            'cat',   null,           true),
  ('Scratching post',                 'cat',   null,           false),
  ('Pet carrier',                     'cat',   null,           false),
  ('Grooming brush',                  'cat',   null,           false),
  ('Grooming brush',                  null,    'cat_persian',  true),

  ('Dry dog food',                    'dog',   null,           true),
  ('Collar and leash',                'dog',   null,           true),
  ('Food and water bowls',            'dog',   null,           true),
  ('Chew toy',                        'dog',   null,           false),
  ('Dog bed',                         'dog',   null,           false),
  ('Grooming brush',                  'dog',   null,           false),
  ('Pet carrier',                     'dog',   null,           false),

  ('Bird cage',                       'bird',  null,           true),
  ('Seed mix',                        'bird',  null,           true),
  ('Seed feeder and water dispenser', 'bird',  null,           true),
  ('Cuttlebone (calcium)',            'bird',  null,           false),
  ('Perches and swings',              'bird',  null,           false)
) as v(item_name, kind, taxon_key, essential)
join public.catalogue_items i on i.name_en = v.item_name
left join public.taxa t on t.key = v.taxon_key;
