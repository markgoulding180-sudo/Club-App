-- TEST DATA for the TEST database only (Club-APP-test). Run after setup-test-database.sql.
-- Every login's password is: railway
--   mark@railway.com      App admin (everything, Features, Roles, View as)
--   sam@railway.com       Bar Manager      stuart@railway.com  Secretary
--   jason@, jackie@       Entertainments committee
--   adam@, heather@, luis@, yannika@, joe@, jamie@, larry@railway.com   staff
--   committee@railway.com, admin@railway.com, firstname.surname@members.test   members
-- Never run this on the live project.

-- App admin for testing
do $$
declare uid uuid;
begin
  select id into uid from auth.users where lower(email) = 'mark@railway.com';
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'mark@railway.com',
      extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
      jsonb_build_object('first_name', 'Mark', 'last_name', 'Goulding'), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', 'mark@railway.com', 'email_verified', true), 'email', now(), now(), now());
  end if;
  insert into public.profiles (id, email, first_name, last_name) values (uid, 'mark@railway.com', 'Mark', 'Goulding') on conflict (id) do nothing;
  update public.profiles set role = 'admin', title = 'App admin', perms = array['owner'] where id = uid;
end $$;


-- ===== add-club-officers.sql =====
-- Club officers: logins (password: railway) with their roles and permissions.
--   Stuart Fraser  stuart@railway.com  Secretary                 (admin side)
--   Sam Ashman     sam@railway.com     Bar Manager               (admin: rota, staff, bookings, tickets, messages, notices, jobs, What's On)
--   Jason Wilson   jason@railway.com   Entertainments committee  (member + manage What's On)
--   Jackie Apps    jackie@railway.com  Entertainments committee  (member + manage What's On)
-- Safe to run more than once.
do $$
declare
  r record; uid uuid;
begin
  for r in select * from (values
      ('stuart@railway.com', 'Stuart', 'Fraser', 'admin', 'Secretary',      array[]::text[]),
      ('sam@railway.com',    'Sam',    'Ashman', 'admin', 'Bar Manager',    array['bookings','rota','staff','tickets','messages','notices','jobs','whatson']),
      ('jason@railway.com',  'Jason',  'Wilson', 'user',  'Entertainments', array['whatson']),
      ('jackie@railway.com', 'Jackie', 'Apps',   'user',  'Entertainments', array['whatson'])
    ) as t(email, first_name, last_name, role, title, perms)
  loop
    select id into uid from auth.users where lower(email) = r.email;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', r.email,
        extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
        jsonb_build_object('first_name', r.first_name, 'last_name', r.last_name), now(), now(), '', '', '', '');
      insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', r.email, 'email_verified', true), 'email', now(), now(), now());
    else
      update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
    end if;

    insert into public.profiles (id, email, first_name, last_name) values (uid, r.email, r.first_name, r.last_name)
    on conflict (id) do nothing;
    update public.profiles set first_name = r.first_name, last_name = r.last_name, email = r.email,
      role = r.role, title = r.title, perms = r.perms, skill = null, regular_shifts = '[]'::jsonb
    where id = uid;
  end loop;
end $$;

-- Check
select first_name, last_name, email, role, title, perms from public.profiles order by role, title, last_name;

-- ===== add-staff.sql =====
-- Bar / door staff logins (password: railway). They start with no regular shifts; set those on the Staff page.
-- Safe to run more than once.
do $$
declare
  r record; uid uuid;
begin
  for r in select * from (values
      ('adam@railway.com',    'Adam',    'Varley',         'staff', null::text, array[]::text[]),
      ('yannika@railway.com', 'Yannika', 'Jackson',        'staff', null, array[]::text[]),
      ('heather@railway.com', 'Heather', 'Fraser Lambert', 'staff', null, array[]::text[]),
      ('luis@railway.com',    'Luis',    'Beaumont',       'staff', null, array[]::text[]),
      ('joe@railway.com',     'Joe',     'Blogs',          'staff', null, array[]::text[]),
      ('jamie@railway.com',   'Jamie',   'Preston',        'staff', null, array[]::text[]),
      ('larry@railway.com',   'Larry',   'Goldsmith',      'staff', null, array[]::text[])
    ) as t(email, first_name, last_name, role, title, perms)
  loop
    select id into uid from auth.users where lower(email) = r.email;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', r.email,
        extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
        jsonb_build_object('first_name', r.first_name, 'last_name', r.last_name), now(), now(), '', '', '', '');
      insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', r.email, 'email_verified', true), 'email', now(), now(), now());
    else
      update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
    end if;

    insert into public.profiles (id, email, first_name, last_name) values (uid, r.email, r.first_name, r.last_name)
    on conflict (id) do nothing;
    update public.profiles set first_name = r.first_name, last_name = r.last_name, email = r.email,
      role = r.role, title = r.title, perms = r.perms, skill = 'both', regular_shifts = '[]'::jsonb
    where id = uid;
  end loop;
end $$;

-- Check
select first_name, last_name, email, role, title, perms from public.profiles order by role, title, last_name;

-- ===== set-staff-hours.sql =====
-- Full time: Adam, Luis, Yannika, Heather (regular weekly shifts, at least 2 days off each).
-- Part time: Joe, Jamie, Larry (no regular shifts, used as and when).
-- Door only: Larry. Yannika works bar and door.
-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat.
-- Between them the full-timers cover every regular shift: Lounge Bar every evening, Lounge Bar daytime Fri/Sat/Sun/Mon, Door every evening.

update public.profiles set skill = 'both', regular_shifts =      -- Yannika: Door, Wed to Sun evenings (off Mon, Tue)
  '[{"d":3,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"door"},{"d":5,"s":"eve","j":"door"},{"d":6,"s":"eve","j":"door"},{"d":0,"s":"eve","j":"door"}]'
  where lower(email) = 'yannika@railway.com';
update public.profiles set skill = 'both', regular_shifts =      -- Luis: Mon day bar, Tue eve door, Thu eve bar, Fri eve bar, Sun day bar (off Wed, Sat)
  '[{"d":1,"s":"day","j":"lounge"},{"d":2,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"lounge"},{"d":5,"s":"eve","j":"lounge"},{"d":0,"s":"day","j":"lounge"}]'
  where lower(email) = 'luis@railway.com';
update public.profiles set skill = 'both', regular_shifts =      -- Adam: Mon eve door, Tue eve bar, Fri day bar, Sat eve bar (off Wed, Thu, Sun)
  '[{"d":1,"s":"eve","j":"door"},{"d":2,"s":"eve","j":"lounge"},{"d":5,"s":"day","j":"lounge"},{"d":6,"s":"eve","j":"lounge"}]'
  where lower(email) = 'adam@railway.com';
update public.profiles set skill = 'both', regular_shifts =      -- Heather: Mon eve bar, Wed eve bar, Sat day bar, Sun eve bar (off Tue, Thu, Fri)
  '[{"d":1,"s":"eve","j":"lounge"},{"d":3,"s":"eve","j":"lounge"},{"d":6,"s":"day","j":"lounge"},{"d":0,"s":"eve","j":"lounge"}]'
  where lower(email) = 'heather@railway.com';

-- Part time
update public.profiles set skill = 'door', regular_shifts = '[]'::jsonb where lower(email) = 'larry@railway.com';
update public.profiles set skill = 'both', regular_shifts = '[]'::jsonb where lower(email) in ('joe@railway.com', 'jamie@railway.com');

-- Check
select first_name, last_name, case when jsonb_array_length(regular_shifts) > 0 then 'Full time' else 'Part time' end as hours,
       skill, jsonb_array_length(regular_shifts) as shifts_a_week
from public.profiles where role = 'staff' order by hours, first_name;

-- ===== add-members-bookings.sql =====
-- 12 members, each with an app login (password: railway), a membership number on the register,
-- and a room-hire booking linked to their account. Confirmed bookings have their £100 deposit paid;
-- pending ones are waiting for the club to confirm.
-- Logins: firstname.surname@members.test   Membership numbers: ARC-1001 to ARC-1012
-- Dates avoid the club events and league nights. Safe to run again.
do $$
declare r record; uid uuid; bid bigint;
begin
  delete from public.bookings where event_details->>'src' = 'members-2026';

  for r in select * from (values
    ('ARC-1001', 'Chloe',    'Martin',  'Full',   '07700 900301', 'hall',   '2026-11-06', 'evening',   'confirmed', '18th Birthday',      80, 'DJ booked. Buffet at 9pm.',              250),
    ('ARC-1002', 'Sarah',    'Hughes',  'Full',   '07700 900302', 'lounge', '2026-11-08', 'afternoon', 'confirmed', 'Christening',        35, 'Cake on arrival.',                        90),
    ('ARC-1003', 'Dean',     'Fletcher','Full',   '07700 900303', 'hall',   '2026-11-13', 'evening',   'confirmed', 'Birthday',           90, '50th birthday. Band 8pm to 11pm.',       250),
    ('ARC-1004', 'Gary',     'Allen',   'Senior', '07700 900304', 'lounge', '2026-11-16', 'evening',   'confirmed', 'Meeting',            20, 'Allotment society AGM. Tables in rows.',  80),
    ('ARC-1005', 'Margaret', 'Doyle',   'Senior', '07700 900305', 'hall',   '2026-11-20', 'afternoon', 'confirmed', 'Wake',               60, 'Sandwiches and tea urn.',                180),
    ('ARC-1006', 'Priya',    'Kapoor',  'Family', '07700 900306', 'hall',   '2026-11-27', 'evening',   'pending',   'Engagement',        100, 'Asking about decorations from 4pm.',     250),
    ('ARC-1007', 'Liam',     'Walsh',   'Full',   '07700 900307', 'lounge', '2026-11-29', 'evening',   'pending',   'Birthday',           40, '30th birthday.',                         120),
    ('ARC-1008', 'Kevin',    'Ward',    'Full',   '07700 900308', 'lounge', '2026-12-07', 'evening',   'confirmed', 'Meeting',            15, 'Darts committee meeting.',                80),
    ('ARC-1009', 'Julie',    'Ellis',   'Full',   '07700 900309', 'hall',   '2026-12-11', 'evening',   'confirmed', 'Club function',     110, 'Works Christmas party. Hot buffet.',     250),
    ('ARC-1010', 'Emma',     'Ross',    'Family', '07700 900310', 'hall',   '2026-12-12', 'afternoon', 'confirmed', 'Birthday',           40, 'Kids 7th birthday. Bouncy castle.',      180),
    ('ARC-1011', 'Jade',     'Turner',  'Full',   '07700 900311', 'hall',   '2026-12-18', 'evening',   'confirmed', 'Wedding reception', 120, 'Evening reception. First dance 8:30pm.', 250),
    ('ARC-1012', 'Brian',    'Cooke',   'Senior', '07700 900312', 'lounge', '2026-12-27', 'afternoon', 'pending',   'Anniversary',        30, '40th wedding anniversary.',               90)
  ) v(no, fn, ln, tier, ph, room, d, slot, st, etype, guests, notes, price)
  loop
    -- Register
    insert into public.club_members (membership_no, first_name, last_name, tier, active) values (r.no, r.fn, r.ln, r.tier, true)
    on conflict (membership_no) do update set first_name = excluded.first_name, last_name = excluded.last_name, tier = excluded.tier, active = true;

    -- Login
    select id into uid from auth.users where lower(email) = lower(r.fn || '.' || r.ln || '@members.test');
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', lower(r.fn || '.' || r.ln || '@members.test'),
        extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
        jsonb_build_object('first_name', r.fn, 'last_name', r.ln), now(), now(), '', '', '', '');
      insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', lower(r.fn || '.' || r.ln || '@members.test'), 'email_verified', true), 'email', now(), now(), now());
    end if;
    insert into public.profiles (id, email, first_name, last_name) values (uid, lower(r.fn || '.' || r.ln || '@members.test'), r.fn, r.ln)
    on conflict (id) do nothing;
    update public.profiles set first_name = r.fn, last_name = r.ln, phone = r.ph, membership_no = r.no,
      role = 'user', title = null, perms = '{}', skill = null where id = uid;

    -- Booking
    insert into public.bookings (booking_kind, room, booking_date, slot, status, user_id, first_name, last_name, customer_phone, customer_email,
      event_type, guests, notes, price, deposit_required, event_details)
    values ('member', r.room, r.d::date, r.slot, r.st, uid, r.fn, r.ln, r.ph, lower(r.fn || '.' || r.ln || '@members.test'),
      r.etype, r.guests, r.notes, r.price, 100, jsonb_build_object('src', 'members-2026'))
    returning id into bid;
    if r.st = 'confirmed' then
      insert into public.payments (booking_id, user_id, amount, kind, method, paid_on, note)
      values (bid, uid, 100, 'deposit', 'card', current_date, 'Deposit');
    end if;
  end loop;
end $$;

-- Check
select b.booking_date, b.room, b.slot, b.status, b.event_type, p.first_name || ' ' || p.last_name as member, p.membership_no, p.email,
       coalesce((select sum(amount) from public.payments x where x.booking_id = b.id), 0) as paid
from public.bookings b join public.profiles p on p.id = b.user_id
where b.event_details->>'src' = 'members-2026' order by b.booking_date;

-- ===== add-whats-on-nov-dec.sql =====
-- What's On: November & December 2026 club events (from the posters) and festive opening times. No sample bookings.
-- Safe to run again: it removes these first, then adds them.
delete from public.bookings where booking_kind = 'club' and event_details->>'src' = 'poster-2026';
delete from public.events where description like '%(festive opening)%';

-- 1) Club events: Function Room
insert into public.bookings (booking_kind, event_type, first_name, last_name, room, booking_date, slot, start_time, end_time,
  ticketed, price_member, price_guest, tickets_total, bar_staff, notes, status, price, deposit_required, event_details)
select 'club', t, 'Club', 'event', 'hall', d::date, s, st::time, en::time, tk, pm, pg, tt, bar, n, 'confirmed', null, 0,
       jsonb_build_object('cat', c, 'src', 'poster-2026')
from (values
  ('Race Night',            '2026-11-07', 'evening',   '20:00', '23:00', false, null::numeric, null::numeric, null::int, 1, 'Have a flutter on the horses. Everyone welcome.', 'race'),
  ('Bingo',                 '2026-11-08', 'evening',   '20:00', '22:30', false, null, null, null, 1, 'Sunday bingo. Eyes down at 8pm.', 'bingo'),
  ('Grooveshack',           '2026-11-14', 'evening',   '20:00', '23:00', true,  5, 8, 100, 2, 'Grooveshack singing group. Ticket event.', 'music'),
  ('Hoy Bingo',             '2026-11-21', 'evening',   '20:00', '22:30', false, null, null, null, 1, 'Hoy bingo night.', 'bingo'),
  ('Bingo',                 '2026-11-22', 'evening',   '20:00', '22:30', false, null, null, null, 1, 'Sunday bingo. Eyes down at 8pm.', 'bingo'),
  ('Abi Nash',              '2026-11-28', 'evening',   '20:00', '23:00', false, null, null, null, 2, 'Live music from singer Abi Nash.', 'music'),
  ('Christmas Karaoke',     '2026-12-05', 'evening',   '20:00', '23:00', false, null, null, null, 1, 'Festive karaoke. Christmas jumpers welcome.', 'karaoke'),
  ('Bingo',                 '2026-12-06', 'evening',   '20:00', '22:30', false, null, null, null, 1, 'Sunday bingo. Eyes down at 8pm.', 'bingo'),
  ('Kids Christmas Party',  '2026-12-13', 'afternoon', '12:00', '16:00', false, null, null, null, 1, 'Games, party food and a visit from Santa.', 'none'),
  ('Hoy Bingo',             '2026-12-19', 'evening',   '20:00', '22:30', false, null, null, null, 1, 'Christmas hoy bingo.', 'bingo'),
  ('Bingo',                 '2026-12-20', 'evening',   '20:00', '22:30', false, null, null, null, 1, 'Sunday bingo. Eyes down at 8pm.', 'bingo'),
  ('Boxing Day Disco',      '2026-12-26', 'afternoon', '12:00', '16:00', false, null, null, null, 2, 'Boxing Day disco. Club open 10am–4pm.', 'music'),
  ('New Year''s Eve Party', '2026-12-31', 'evening',   '19:00', '01:00', true,  10, 15, 120, 2, 'See in 2027 with us. Ticket event only. Open till 1am.', 'music')
) v(t, d, s, st, en, tk, pm, pg, tt, bar, n, c);

-- 2) Festive opening times (shown on What's On)
insert into public.events (title, category, description, starts_at) values
  ('Christmas Day opening', 'Other', 'Open 12pm – 2pm. Merry Christmas! (festive opening)', timestamp '2026-12-25 12:00' at time zone 'Europe/London'),
  ('Boxing Day opening',    'Other', 'Open 10am – 4pm, with a disco 12pm – 4pm. (festive opening)', timestamp '2026-12-26 10:00' at time zone 'Europe/London'),
  ('New Year''s Day opening','Other', 'Open 12pm – 2pm. Happy New Year! (festive opening)', timestamp '2027-01-01 12:00' at time zone 'Europe/London');

-- Check
select booking_date, event_type, slot, start_time, end_time, case when ticketed then 'Tickets' else '' end as tickets
from public.bookings where event_details->>'src' = 'poster-2026' order by booking_date;
select title, starts_at at time zone 'Europe/London' as opens from public.events where description like '%(festive opening)%' order by starts_at;

-- ===== add-leagues.sql =====
-- Weekly league nights in the Lounge Bar, 8pm to 11pm, from 3 Nov 2026 to the Christmas break (none 21 Dec to 3 Jan).
--   Tuesday   Darts Ladies League
--   Wednesday Wednesday Darts League
--   Thursday  Pool League
--   Friday    Darts Ashford League
-- They show in the bookings diary and on the rota. Like all league nights they stay off the public What's On.
-- Safe to run again: it removes these first, then adds them.
delete from public.bookings where event_details->>'src' = 'league-2026';

insert into public.bookings (booking_kind, event_type, first_name, last_name, room, booking_date, slot, start_time, end_time,
  ticketed, price_member, price_guest, tickets_total, bar_staff, notes, status, price, deposit_required, event_details)
select 'club', l.name, 'Club', 'sports', 'lounge', d::date, 'evening', '20:00', '23:00',
       false, null, null, null, 1, '', 'confirmed', null, 0,
       jsonb_build_object('sport', true, 'cat', l.cat, 'series', 'league-' || l.dow, 'src', 'league-2026')
from (values (2, 'Darts Ladies League', 'darts'),
             (3, 'Wednesday Darts League', 'darts'),
             (4, 'Pool League', 'pool'),
             (5, 'Darts Ashford League', 'darts')) l(dow, name, cat)
cross join generate_series(date '2026-11-02', date '2026-12-20', interval '1 day') d
where extract(dow from d) = l.dow;

-- Check
select event_type, to_char(min(booking_date), 'Dy DD Mon') as first_night, to_char(max(booking_date), 'Dy DD Mon') as last_night, count(*) as nights
from public.bookings where event_details->>'src' = 'league-2026' group by event_type order by min(booking_date);

-- ===== add-premier-league-mondays.sql =====
-- Ashford Premier League darts: Mondays, 7pm to 11pm, Lounge Bar, 2 Nov to 14 Dec 2026 (break for Christmas like the other leagues).
-- League nights stay off the public What's On, but show in Bookings and on the rota.
-- Club bookings take priority: if a member has the Lounge Bar that evening, the league still goes in and the double booking is listed at the end. Safe to run again.
delete from public.bookings where event_details->>'src' = 'league-2026' and event_type = 'Ashford Premier League';
do $$
declare d date; skipped text := '';
begin
  for d in select g::date from generate_series(date '2026-11-02', date '2026-12-14', interval '7 days') g loop
    begin
      insert into public.bookings (booking_kind, event_type, first_name, last_name, room, booking_date, slot, start_time, end_time,
        ticketed, price_member, price_guest, tickets_total, bar_staff, notes, status, price, deposit_required, event_details)
      values ('club', 'Ashford Premier League', 'Club', 'sports', 'lounge', d, 'evening', '19:00', '23:00',
        false, null, null, null, 1, 'Darts', 'confirmed', null, 0,
        jsonb_build_object('sport', true, 'cat', 'darts', 'series', 'league-1', 'src', 'league-2026'));
    exception when others then skipped := skipped || to_char(d, 'Dy DD Mon') || ' (' || sqlerrm || ')  ';
    end;
  end loop;
  if skipped <> '' then raise notice 'Skipped: %', skipped; end if;
end $$;

-- Check: the Mondays added, and any Monday that clashed
select to_char(booking_date, 'Dy DD Mon') as night, start_time, end_time, room from public.bookings
where event_type = 'Ashford Premier League' order by booking_date;
select to_char(b.booking_date, 'Dy DD Mon') as double_booked, coalesce(b.event_type, 'booking') || ' · ' || b.first_name || ' ' || b.last_name as member_booking_to_move
from public.bookings b
where b.room = 'lounge' and b.status <> 'cancelled' and extract(dow from b.booking_date) = 1 and b.booking_date between '2026-11-02' and '2026-12-14'
  and b.slot in ('evening', 'full_day') and b.event_type <> 'Ashford Premier League' order by b.booking_date;

-- ===== add-premier-league-tv.sql =====
-- Live Sport Shown: Premier League games on UK TV, 6 Nov 2026 to 7 Jan 2027 (Sky Sports and TNT Sports).
-- Shows in What's On → Live Sport Shown. Clears any Premier League games already listed from today on first,
-- so it's safe to run again. Source: live-footballontv.com, 3 Nov 2026. Times are UK time.
delete from public.events where category = 'Sport' and description like 'Premier League%' and starts_at >= date_trunc('day', now());
insert into public.events (title, description, category, starts_at)
select title, description, 'Sport', (ts::timestamp at time zone 'Europe/London') from (values
  ('Everton v Coventry City', 'Premier League · Sky Sports Main Event', '2026-11-06 20:00'),
  ('Leeds United v Tottenham Hotspur', 'Premier League · TNT Sports 1', '2026-11-07 12:30'),
  ('Nottingham Forest v Manchester City', 'Premier League · Sky Sports Main Event', '2026-11-07 17:30'),
  ('Brighton & Hove Albion v Brentford', 'Premier League · Sky Sports+', '2026-11-08 14:00'),
  ('Crystal Palace v Liverpool', 'Premier League · Sky Sports Main Event', '2026-11-08 14:00'),
  ('Ipswich Town v AFC Bournemouth', 'Premier League · Sky Sports Cricket', '2026-11-08 14:00'),
  ('Sunderland v Chelsea', 'Premier League · Sky Sports Premier League', '2026-11-08 14:00'),
  ('Manchester United v Aston Villa', 'Premier League · Sky Sports Main Event', '2026-11-08 16:30'),
  ('Manchester City v Fulham', 'Premier League · TNT Sports 1', '2026-11-21 12:30'),
  ('Newcastle United v Arsenal', 'Premier League · Sky Sports Main Event', '2026-11-21 17:30'),
  ('Hull City v Brighton & Hove Albion', 'Premier League · Sky Sports Main Event', '2026-11-22 14:00'),
  ('Liverpool v Manchester United', 'Premier League · Sky Sports Main Event', '2026-11-22 16:30'),
  ('Brentford v Everton', 'Premier League · Sky Sports Main Event', '2026-11-23 20:00'),
  ('Nottingham Forest v Chelsea', 'Premier League · Sky Sports Main Event', '2026-11-27 20:00'),
  ('Ipswich Town v Aston Villa', 'Premier League · Sky Sports Main Event', '2026-11-28 17:30'),
  ('Everton v Liverpool', 'Premier League · TNT Sports 1', '2026-11-29 12:00'),
  ('Brighton & Hove Albion v Newcastle United', 'Premier League · Sky Sports Premier League', '2026-11-29 14:05'),
  ('Crystal Palace v Hull City', 'Premier League · Sky Sports Cricket', '2026-11-29 14:05'),
  ('Fulham v AFC Bournemouth', 'Premier League · Sky Sports+', '2026-11-29 14:05'),
  ('Sunderland v Tottenham Hotspur', 'Premier League · Sky Sports Main Event', '2026-11-29 14:05'),
  ('Arsenal v Manchester City', 'Premier League · Sky Sports Main Event', '2026-11-29 16:30'),
  ('Coventry City v Ipswich Town', 'Premier League · Sky Sports Main Event', '2026-12-01 20:00'),
  ('Chelsea v Crystal Palace', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 19:30'),
  ('Hull City v Nottingham Forest', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 19:30'),
  ('Liverpool v Sunderland', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 19:30'),
  ('Manchester City v Leeds United', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 19:30'),
  ('AFC Bournemouth v Brighton & Hove Albion', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 20:15'),
  ('Aston Villa v Everton', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 20:15'),
  ('Brentford v Arsenal', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 20:15'),
  ('Newcastle United v Manchester United', 'Premier League · Sky Sports (channel TBC)', '2026-12-02 20:15'),
  ('Tottenham Hotspur v Fulham', 'Premier League · Sky Sports Main Event', '2026-12-03 20:00'),
  ('Chelsea v Liverpool', 'Premier League · TNT Sports 1', '2026-12-05 12:30'),
  ('Nottingham Forest v Brighton & Hove Albion', 'Premier League · Sky Sports Main Event', '2026-12-05 17:30'),
  ('Brentford v Manchester City', 'Premier League · Sky Sports Main Event', '2026-12-05 20:00'),
  ('Everton v Fulham', 'Premier League · Sky Sports (channel TBC)', '2026-12-06 14:00'),
  ('Newcastle United v Sunderland', 'Premier League · Sky Sports (channel TBC)', '2026-12-06 14:00'),
  ('Tottenham Hotspur v Arsenal', 'Premier League · Sky Sports Main Event', '2026-12-06 16:30'),
  ('Manchester City v Chelsea', 'Premier League · Sky Sports Main Event', '2026-12-12 17:30'),
  ('Arsenal v AFC Bournemouth', 'Premier League · Sky Sports (channel TBC)', '2026-12-13 14:00'),
  ('Brighton & Hove Albion v Everton', 'Premier League · Sky Sports (channel TBC)', '2026-12-13 14:00'),
  ('Sunderland v Nottingham Forest', 'Premier League · Sky Sports (channel TBC)', '2026-12-13 14:00'),
  ('Coventry City v Aston Villa', 'Premier League · Sky Sports Main Event', '2026-12-13 16:30'),
  ('Crystal Palace v Manchester United', 'Premier League · TNT Sports 1', '2026-12-13 19:00'),
  ('Hull City v Tottenham Hotspur', 'Premier League · Sky Sports Main Event', '2026-12-14 20:00'),
  ('Brentford v Newcastle United', 'Premier League · TNT Sports 1', '2026-12-19 12:30'),
  ('Liverpool v Tottenham Hotspur', 'Premier League · Sky Sports Main Event', '2026-12-19 17:30'),
  ('Brighton & Hove Albion v Ipswich Town', 'Premier League · Sky Sports+', '2026-12-20 14:00'),
  ('Sunderland v Crystal Palace', 'Premier League · Sky Sports+', '2026-12-20 14:00'),
  ('Arsenal v Manchester United', 'Premier League · Sky Sports Main Event', '2026-12-20 16:30'),
  ('Chelsea v Aston Villa', 'Premier League · Sky Sports Main Event', '2026-12-21 20:00'),
  ('Aston Villa v Leeds United', 'Premier League · TNT Sports 1', '2026-12-26 12:30'),
  ('Hull City v Liverpool', 'Premier League · Sky Sports Main Event', '2026-12-26 17:30'),
  ('Newcastle United v Manchester City', 'Premier League · Sky Sports Main Event', '2026-12-26 20:00'),
  ('Coventry City v Chelsea', 'Premier League · Sky Sports Main Event', '2026-12-27 14:00'),
  ('Manchester United v Nottingham Forest', 'Premier League · Sky Sports Main Event', '2026-12-27 16:30'),
  ('Crystal Palace v Arsenal', 'Premier League · Sky Sports Main Event', '2026-12-27 19:00'),
  ('Hull City v Leeds United', 'Premier League · Sky Sports+', '2026-12-29 19:30'),
  ('Tottenham Hotspur v Brighton & Hove Albion', 'Premier League · Sky Sports Main Event', '2026-12-29 19:30'),
  ('Everton v Manchester City', 'Premier League · Sky Sports Premier League', '2026-12-29 20:15'),
  ('Coventry City v Brentford', 'Premier League · Sky Sports Tennis', '2026-12-30 19:30'),
  ('Crystal Palace v AFC Bournemouth', 'Premier League · Sky Sports Golf', '2026-12-30 19:30'),
  ('Fulham v Arsenal', 'Premier League · Sky Sports Main Event', '2026-12-30 19:30'),
  ('Manchester United v Sunderland', 'Premier League · Sky Sports Premier League', '2026-12-30 19:30'),
  ('Newcastle United v Nottingham Forest', 'Premier League · Sky Sports Cricket', '2026-12-30 19:30'),
  ('Aston Villa v Liverpool', 'Premier League · Sky Sports Football', '2026-12-30 20:15'),
  ('Ipswich Town v Chelsea', 'Premier League · Sky Sports+', '2026-12-30 20:15'),
  ('Leeds United v Everton', 'Premier League · Sky Sports Main Event', '2027-01-01 20:00'),
  ('Brighton & Hove Albion v Manchester United', 'Premier League · TNT Sports 1', '2027-01-02 12:30'),
  ('AFC Bournemouth v Aston Villa', 'Premier League · Sky Sports Main Event', '2027-01-02 17:30'),
  ('Chelsea v Newcastle United', 'Premier League · Sky Sports Main Event', '2027-01-03 14:00'),
  ('Manchester City v Tottenham Hotspur', 'Premier League · Sky Sports Main Event', '2027-01-03 16:30'),
  ('Arsenal v Brentford', 'Premier League · Sky Sports Main Event', '2027-01-05 19:30'),
  ('Brighton & Hove Albion v AFC Bournemouth', 'Premier League · Sky Sports+', '2027-01-05 19:30'),
  ('Everton v Aston Villa', 'Premier League · Sky Sports Football', '2027-01-05 19:30'),
  ('Nottingham Forest v Hull City', 'Premier League · Sky Sports Cricket', '2027-01-05 19:30'),
  ('Sunderland v Liverpool', 'Premier League · Sky Sports Premier League', '2027-01-05 20:15'),
  ('Crystal Palace v Chelsea', 'Premier League · Sky Sports Main Event', '2027-01-06 19:30'),
  ('Fulham v Tottenham Hotspur', 'Premier League · Sky Sports Football', '2027-01-06 19:30'),
  ('Ipswich Town v Coventry City', 'Premier League · Sky Sports+', '2027-01-06 19:30'),
  ('Leeds United v Manchester City', 'Premier League · Sky Sports Premier League', '2027-01-06 20:15'),
  ('Manchester United v Newcastle United', 'Premier League · Sky Sports Main Event', '2027-01-07 20:00')
) v(title, description, ts);

select to_char(starts_at at time zone 'Europe/London', 'Dy DD Mon HH24:MI') as "Kick-off", title as "Game", description as "On"
from public.events where category = 'Sport' and starts_at >= date_trunc('day', now()) order by starts_at;

-- ===== add-committee-login.sql =====
-- One shared login for the committee to look at the members' app.
-- Login: committee@railway.com   Password: railway   (a normal member account). Safe to run again.
do $$
declare uid uuid; stuart uuid;
begin
  insert into public.club_members (membership_no, first_name, last_name, tier, active) values ('ARC-1099', 'Committee', 'Guest', 'Full', true)
  on conflict (membership_no) do update set first_name = excluded.first_name, last_name = excluded.last_name, active = true;

  select id into uid from auth.users where lower(email) = 'committee@railway.com';
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'committee@railway.com',
      extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
      jsonb_build_object('first_name', 'Committee', 'last_name', 'Guest'), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', 'committee@railway.com', 'email_verified', true), 'email', now(), now(), now());
  else
    update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
  end if;
  insert into public.profiles (id, email, first_name, last_name) values (uid, 'committee@railway.com', 'Committee', 'Guest') on conflict (id) do nothing;
  update public.profiles set email = 'committee@railway.com', first_name = 'Committee', last_name = 'Guest', membership_no = 'ARC-1099',
    role = 'user', title = null, perms = '{}', skill = null where id = uid;

  -- A welcome message from the Secretary, so the message board has something in it
  select id into stuart from public.profiles where lower(email) = 'stuart@railway.com';
  if stuart is not null and not exists (select 1 from public.member_messages where recipient = uid and sender = stuart) then
    insert into public.member_messages (sender, recipient, body, subject)
    values (stuart, uid, 'Welcome to the new club app! Have a look round: What''s On, tickets, room hire and the newsletter. You can reply to this message too. Stuart, Secretary', 'Welcome to the club app');
  end if;
end $$;

select email, first_name, last_name, role, membership_no from public.profiles where lower(email) = 'committee@railway.com';

-- ===== add-admin-guest-login.sql =====
-- A shared login so anyone can look at the members' app.
-- Login: admin@railway.com   Password: railway   (a normal member account). Safe to run again.
do $$
declare uid uuid; stuart uuid;
begin
  insert into public.club_members (membership_no, first_name, last_name, tier, active) values ('99', 'Club', 'Guest', 'Full', true)
  on conflict (membership_no) do update set first_name = excluded.first_name, last_name = excluded.last_name, active = true;

  select id into uid from auth.users where lower(email) = 'admin@railway.com';
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'admin@railway.com',
      extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
      jsonb_build_object('first_name', 'Club', 'last_name', 'Guest'), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', 'admin@railway.com', 'email_verified', true), 'email', now(), now(), now());
  else
    update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
  end if;
  insert into public.profiles (id, email, first_name, last_name) values (uid, 'admin@railway.com', 'Club', 'Guest') on conflict (id) do nothing;
  update public.profiles set email = 'admin@railway.com', first_name = 'Club', last_name = 'Guest', membership_no = '99',
    role = 'user', title = null, perms = '{}', skill = null where id = uid;

  -- A welcome message from the Secretary, so the message board has something in it
  select id into stuart from public.profiles where lower(email) = 'stuart@railway.com';
  if stuart is not null and not exists (select 1 from public.member_messages where recipient = uid and sender = stuart) then
    insert into public.member_messages (sender, recipient, body, subject)
    values (stuart, uid, 'Welcome to the new club app! Have a look round: What''s On, tickets, room hire and the newsletter. You can reply to this message too. Stuart, Secretary', 'Welcome to the club app');
  end if;
end $$;

select email, first_name, last_name, role, membership_no from public.profiles where lower(email) = 'admin@railway.com';

-- ===== number-members.sql =====
-- Membership numbers 1, 2, 3 … for every member on the app (oldest account first),
-- kept in step with the membership register and ticket reservations. Members can then find each other
-- under Friends by typing the number, e.g. 9. Staff and officers aren't numbered. Safe to run once;
-- running it again renumbers in the same order.

-- Allow short numbers like 9 (it used to need at least 2 characters)
alter table public.club_members drop constraint if exists club_members_membership_no_check;
alter table public.club_members add constraint club_members_membership_no_check check (membership_no ~ '^[A-Za-z0-9-]{1,20}$');

do $$
declare r record; n int := 0; old text; t text;
begin
  -- Park everyone's current number first, so new numbers never clash with old ones
  create temp table renum on commit drop as
    select p.id, p.membership_no as old_no, p.first_name, p.last_name, row_number() over (order by u.created_at, p.last_name, p.first_name) as new_no
    from public.profiles p left join auth.users u on u.id = p.id
    where p.role = 'user' and p.first_name is not null;

  for r in select * from renum order by new_no loop
    -- Tier from their old register row, if they had one
    select c.tier into t from public.club_members c where upper(c.membership_no) = upper(coalesce(r.old_no, '')) limit 1;
    delete from public.club_members c where upper(c.membership_no) = upper(coalesce(r.old_no, '')) and lower(c.last_name) = lower(coalesce(r.last_name, ''));
    insert into public.club_members (membership_no, first_name, last_name, tier, active)
    values (r.new_no::text, r.first_name, coalesce(nullif(r.last_name, ''), '-'), coalesce(t, 'Full'), true)
    on conflict (membership_no) do update set first_name = excluded.first_name, last_name = excluded.last_name, tier = excluded.tier, active = true;
    update public.profiles set membership_no = r.new_no::text where id = r.id;
    update public.ticket_reservations set membership_no = r.new_no::text where user_id = r.id;
    t := null;
  end loop;
end $$;

select p.membership_no as "Number", p.first_name || ' ' || coalesce(p.last_name, '') as "Member", p.email
from public.profiles p where p.role = 'user' order by p.membership_no::int;

-- ===== reset-and-send-messages.sql =====
-- Run update-message-titles.sql first.
-- Clears ALL messages (staff messages, notices, member messages, read/hidden marks), then sends a fresh set,
-- each with the right sender so the photos show. If there's no Secretary yet, his messages are skipped. Holidays, shifts and swaps are left alone. Safe to run again.
do $$
declare heather uuid; adam uuid; luis uuid; sam uuid; stuart uuid; mark uuid; jason uuid; jackie uuid; joe uuid; jamie uuid; yannika uuid; chloe uuid;
begin
  select id into heather from public.profiles where lower(email) = 'heather@railway.com';
  select id into adam    from public.profiles where lower(email) = 'adam@railway.com';
  select id into luis    from public.profiles where lower(email) = 'luis@railway.com';
  select id into sam     from public.profiles where role = 'admin' and (lower(email) like 'sam%@railway.com' or title ilike '%bar manager%') order by (lower(email) like 'sam%') desc limit 1;
  select id into stuart  from public.profiles where lower(email) = 'stuart@railway.com';
  if stuart is null then select id into stuart from public.profiles where role = 'admin' and title ilike '%secretary%' limit 1; end if;
  select id into mark    from public.profiles where lower(email) = 'markgoulding180@gmail.com';
  select id into jason   from public.profiles where lower(email) like 'jason%@railway.com' limit 1;
  select id into jackie  from public.profiles where lower(email) like 'jackie%@railway.com' limit 1;
  select id into joe     from public.profiles where lower(email) = 'joe@railway.com';
  select id into jamie   from public.profiles where lower(email) = 'jamie@railway.com';
  select id into yannika from public.profiles where lower(email) = 'yannika@railway.com';
  select id into chloe   from public.profiles where lower(email) = 'chloe.martin@members.test';

  if sam is null then raise exception 'Can''t find Sam the Bar Manager.'; end if;

  -- Clear everything
  delete from public.hidden_messages;
  delete from public.notice_reads;
  delete from public.club_notices;
  delete from public.staff_messages;
  delete from public.member_messages;

  -- 📋 Secretary (Stuart) to all staff
  insert into public.club_notices (title, body, audience, created_by, created_at)
  select 'Fire drill', 'There''s a fire drill on Mon 16 Nov at 6pm. Please make sure you know where the assembly point is (front car park). Stuart', 'staff', stuart, now() - interval '58 minutes' where stuart is not null;

  -- 📋 Secretary (Stuart) to members
  insert into public.club_notices (title, body, audience, created_by, created_at)
  select 'Membership renewals', 'Membership renewals for 2027 open on Tue 1 Dec. You can pay at the bar or in the office. Stuart, Secretary', 'members', stuart, now() - interval '52 minutes' where stuart is not null;

  -- 🏛 The club (Mark) to all staff
  insert into public.club_notices (title, body, audience, created_by, created_at)
  values ('Your Messages page', 'Messages from management are under Management, and chats with other staff are under Staff. Mark', 'staff', mark, now() - interval '47 minutes');

  -- 🍺 Manager (Sam) to Heather only, and a reply to her message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Christmas Eve', 'Hi Heather, would you like to work Christmas Eve day shift 12 till 6? Double time. Sam', 'staff', heather, sam, now() - interval '33 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (heather, 'other', 'Can we get more lemons in? We ran out on Saturday night.', 'done', 'Good shout Heather, I''ve doubled the order from this week. Sam', now() - interval '22 minutes', sam, now() - interval '100 minutes');

  -- 🍺 Manager (Sam) to Adam only, and a reply to his message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Stock take', 'Hi Adam, stock take is Sun 29 Nov at 10am. Can you help me with the cellar? Sam', 'staff', adam, sam, now() - interval '28 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (adam, 'club_problem', 'The light in the gents is flickering.', 'done', 'Thanks Adam, electrician is coming Thursday. Sam', now() - interval '18 minutes', sam, now() - interval '5 hours');

  -- New from Jamie, waiting for the manager
  insert into public.staff_messages (staff_id, topic, body, status, created_at)
  values (jamie, 'other', 'Could I swap to door on Fridays instead of bar? I''ve done my door badge.', 'new', now() - interval '11 minutes');

  -- 👥 Staff chats, as back-and-forth conversations (older ones already read)
  -- Adam and Sam: card machine
  insert into public.member_messages (sender, recipient, body, created_at, read_at) values
    (adam, sam,   'Sam, the card machine in the Lounge Bar keeps dropping signal.', now() - interval '70 minutes', now() - interval '65 minutes'),
    (sam,  adam,  'Thanks Adam. Try moving it nearer the till, the signal is better there. I''ll ring the bank tomorrow.', now() - interval '60 minutes', now() - interval '55 minutes'),
    (adam, sam,   'Moved it, working fine now. Cheers.', now() - interval '50 minutes', now() - interval '45 minutes'),
    (sam,  adam,  'Great, nice one. Can you keep an eye on it tonight and let me know if it drops again?', now() - interval '9 minutes', null);

  -- Joe and Adam: Carling barrel
  if joe is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (joe,  adam, 'Adam, how do you change the Carling barrel? I''m on my own Thursday.', now() - interval '80 minutes', now() - interval '75 minutes'),
      (adam, joe,  'Turn the gas off at the wall first, then twist the coupler off the old keg and onto the new one. Gas back on and pull through till it runs clear.', now() - interval '72 minutes', now() - interval '68 minutes'),
      (joe,  adam, 'Where are the spare kegs kept?', now() - interval '66 minutes', now() - interval '64 minutes'),
      (adam, joe,  'Left side of the cellar, behind the Guinness. Shout if you get stuck!', now() - interval '62 minutes', null);
  end if;

  -- Luis and Heather: lift on Friday
  if luis is not null and heather is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (luis,    heather, 'Heather, are you on Friday? I can give you a lift if you want.', now() - interval '40 minutes', now() - interval '36 minutes'),
      (heather, luis,    'Yes please! I start at 6. Could you pick me up at 5:40?', now() - interval '34 minutes', now() - interval '30 minutes'),
      (luis,    heather, 'No problem, see you at 5:40 outside yours.', now() - interval '13 minutes', null);
  end if;

  -- Yannika and Heather: jacket (Heather hasn't replied yet)
  if yannika is not null and heather is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (yannika, heather, 'Hey Heather, did you leave your black jacket in the staff room? It''s on the hook by the door.', now() - interval '20 minutes', null);
  end if;

  -- Heather to Sam: no reply yet
  if heather is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (heather, sam, 'Sam, can I bring my sister to the staff Christmas do?', now() - interval '16 minutes', null);
  end if;

  -- Member: the Secretary to Chloe, and her reply
  if chloe is not null and stuart is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (stuart, chloe, 'Hi Chloe, hope the party went well! Your deposit will be back in your account within 5 days. Stuart, Secretary', now() - interval '44 minutes');
    insert into public.member_messages (sender, recipient, body, created_at)
    values (chloe, stuart, 'It was brilliant, thanks so much!', now() - interval '31 minutes');
  end if;

  -- Committee: Jason (Entertainments) to Stuart
  if jason is not null and stuart is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (jason, stuart, 'Hi Stuart, the band for New Year''s Eve have confirmed. Can you pay their deposit? Jason', now() - interval '5 minutes');
  end if;

  -- Titles for each conversation (needs update-message-titles.sql)
  update public.member_messages set subject = 'Card machine' where (sender = adam and recipient = sam) or (sender = sam and recipient = adam);
  update public.member_messages set subject = 'Changing the Carling barrel' where (sender = joe and recipient = adam) or (sender = adam and recipient = joe);
  update public.member_messages set subject = 'Lift on Friday' where (sender = luis and recipient = heather) or (sender = heather and recipient = luis);
  update public.member_messages set subject = 'Your black jacket' where sender = yannika and recipient = heather;
  update public.member_messages set subject = 'Staff Christmas do' where sender = heather and recipient = sam;
  update public.member_messages set subject = 'Your party on Fri 6 Nov' where (sender = stuart and recipient = chloe) or (sender = chloe and recipient = stuart);
  update public.member_messages set subject = 'New Year''s Eve band' where sender = jason and recipient = stuart;
end $$;

select 'notice' as kind, n.title as what, coalesce(p.first_name, '?') as from_who, coalesce(t.first_name, 'all ' || n.audience) as to_who
from public.club_notices n left join public.profiles p on p.id = n.created_by left join public.profiles t on t.id = n.to_user
union all select 'staff msg', left(m.body, 40), s.first_name, coalesce('reply by ' || r.first_name, 'waiting') from public.staff_messages m join public.profiles s on s.id = m.staff_id left join public.profiles r on r.id = m.replied_by
union all select 'member msg', coalesce(m.subject, '') || ': ' || left(m.body, 30), a.first_name, b.first_name from public.member_messages m join public.profiles a on a.id = m.sender join public.profiles b on b.id = m.recipient;

-- ===== add-todo-demo-messages.sql =====
-- Demo messages to show "+ To-do": jobs and orders from Adam (staff) and Sam (Bar Manager).
-- Adds to what's there (doesn't clear anything). Run add-todo-list.sql first.
do $$
declare adam uuid; sam uuid; stuart uuid;
begin
  select id into adam   from public.profiles where lower(email) = 'adam@railway.com';
  select id into sam    from public.profiles where lower(email) = 'sam@railway.com';
  select id into stuart from public.profiles where lower(email) = 'stuart@railway.com';
  if adam is null or sam is null or stuart is null then raise exception 'Can''t find Adam, Sam or Stuart.'; end if;

  -- Adam → the manager (shows for Sam and Stuart under Messages from staff)
  insert into public.staff_messages (staff_id, topic, body, status, created_at) values
    (adam, 'club_problem', 'We''re down to the last box of crisps and the Coke syrup is nearly out.', 'new', now() - interval '25 minutes'),
    (adam, 'club_problem', 'The lock on the ladies'' toilet door is broken again.', 'new', now() - interval '12 minutes');

  -- Adam → Sam (chat)
  insert into public.member_messages (sender, recipient, body, subject, created_at) values
    (adam, sam, 'Sam, the cellar cooler is making a loud rattling noise. Might need an engineer.', 'Cellar cooler', now() - interval '20 minutes');

  -- Sam → Stuart (chats)
  insert into public.member_messages (sender, recipient, body, subject, created_at) values
    (sam, stuart, 'Stuart, can you put an order in for Friday: 4 kegs of Carling, 2 of Guinness and a box of lemons?', 'Order for Friday', now() - interval '15 minutes'),
    (sam, stuart, 'The fire extinguishers are due their yearly check this month. Can you book it?', 'Fire extinguisher check', now() - interval '8 minutes');
end $$;

select 'staff msg' as kind, left(body, 50) as what from public.staff_messages where created_at > now() - interval '1 hour'
union all select coalesce(subject, ''), left(body, 50) from public.member_messages where created_at > now() - interval '30 minutes';
