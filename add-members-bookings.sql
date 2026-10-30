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
