begin;
select plan(21);

-- Three people: a phone-verified user, another verified user, and an anonymous guest.
insert into auth.users (id, phone, is_anonymous) values
  ('11111111-1111-4111-8111-111111111111', '+8801711111111', false),
  ('22222222-2222-4222-8222-222222222222', '+8801722222222', false),
  ('33333333-3333-4333-8333-333333333333', null, true);

insert into identifications (id, user_id, requested_category, status, engine, top_confidence)
values ('aaaaaaaa-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'plant', 'confident', 'mock', 0.9),
       ('aaaaaaaa-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', 'plant', 'confident', 'mock', 0.9),
       ('aaaaaaaa-0000-4000-8000-000000000003', '33333333-3333-4333-8333-333333333333', 'cat', 'confident', 'mock', 0.9);

insert into collection_items (id, user_id, kind) values
  ('bbbbbbbb-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', 'plant');

select ok((select count(*) = 1 from profiles where id = '11111111-1111-4111-8111-111111111111'),
          'a profile is created with each new user');

-- Anonymous visitor (no session at all) -----------------------------------------
select _test_login(null);
select ok((select count(*) > 0 from taxa), 'anyone can read species');
select ok((select count(*) > 0 from shops), 'anyone can read shops');
select is((select count(*)::int from identifications), 0, 'no session sees no identifications');
select throws_ok($$ select consume_quota('u:x', 5) $$, '42501', null, 'the quota function is closed to app users');
reset role;

-- Guest (anonymous sign-in) -----------------------------------------------------------
select _test_login('33333333-3333-4333-8333-333333333333', true);
select is((select count(*)::int from identifications), 1, 'a guest sees only their own identification');
select throws_ok($$ insert into collection_items (id, kind) values (gen_random_uuid(), 'cat') $$,
                 '42501', null, 'a guest cannot save to My Collection until the phone is verified');
select throws_ok($$ insert into storage.objects (bucket_id, name) values
                    ('photos', '33333333-3333-4333-8333-333333333333/collection/x.jpg') $$,
                 '42501', null, 'a guest cannot upload collection photos');
select lives_ok($$ insert into flags (identification_id, reason) values
                   ('aaaaaaaa-0000-4000-8000-000000000003', 'wrong_match') $$,
                'a guest can report a wrong result on their own identification');
reset role;

-- Verified user ----------------------------------------------------------------
select _test_login('11111111-1111-4111-8111-111111111111');
select lives_ok($$ insert into collection_items (id, kind, nickname) values
                   ('bbbbbbbb-0000-4000-8000-000000000001', 'plant', 'Balcony money plant') $$,
                'a verified user can save to My Collection');
select lives_ok($$ insert into reminders (id, collection_item_id, type, every_days, next_due) values
                   (gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-000000000001', 'water', 7, current_date) $$,
                'and add a reminder to their own item');
select throws_ok($$ insert into reminders (id, collection_item_id, type, next_due) values
                    (gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-000000000002', 'water', current_date) $$,
                 '42501', null, 'but not to someone else''s item');
select is((select count(*)::int from collection_items), 1, 'they see only their own collection');
select throws_ok($$ insert into flags (identification_id, reason) values
                    ('aaaaaaaa-0000-4000-8000-000000000002', 'wrong_match') $$,
                 '42501', null, 'they cannot flag someone else''s identification');
select lives_ok($$ insert into storage.objects (bucket_id, name) values
                   ('photos', '11111111-1111-4111-8111-111111111111/collection/b1.jpg') $$,
                'they can upload into their own collection folder');
select throws_ok($$ insert into storage.objects (bucket_id, name) values
                    ('photos', '22222222-2222-4222-8222-222222222222/collection/x.jpg') $$,
                 '42501', null, 'but not into another user''s folder');
select throws_ok($$ insert into storage.objects (bucket_id, name) values
                    ('photos', '11111111-1111-4111-8111-111111111111/ident/x.jpg') $$,
                 '42501', null, 'and not into the gateway''s temporary folder');
update taxa set name_en = 'Changed by a user' where key = 'rose';
select lives_ok($$ select log_shop_contact('00000000-0000-4000-8000-000000000001', 'whatsapp') $$,
                'a WhatsApp tap is logged');
reset role;
select is((select name_en from taxa where key = 'rose'), 'Rose', 'a non-admin cannot change reference content');

-- Quota ------------------------------------------------------------------------
select is(array[consume_quota('u:test', 2), consume_quota('u:test', 2), consume_quota('u:test', 2)],
          array[1, 2, null]::int[], 'the daily quota stops at the limit');

-- Account deletion -----------------------------------------------------------------
delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from identifications where user_id = '11111111-1111-4111-8111-111111111111')
        + (select count(*)::int from collection_items where user_id = '11111111-1111-4111-8111-111111111111')
        + (select count(*)::int from reminders where user_id = '11111111-1111-4111-8111-111111111111')
        + (select count(*)::int from profiles where id = '11111111-1111-4111-8111-111111111111')
        + (select count(*)::int from shop_contact_events where user_id = '11111111-1111-4111-8111-111111111111'),
          0, 'deleting the account removes all of the user''s rows');

select * from finish();
rollback;
