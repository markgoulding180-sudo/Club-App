-- November & December 2026 club events (from the posters), opening-time notices, and sample member hall bookings.
-- Safe to run again: it removes these first, then adds them.
delete from public.bookings where booking_kind = 'club' and event_details->>'src' = 'poster-2026';
delete from public.bookings where booking_kind = 'member' and event_details->>'src' = 'sample-2026';
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

-- 3) Sample member bookings (room hire)
with b as (
  insert into public.bookings (booking_kind, room, booking_date, slot, status, user_id, first_name, last_name, customer_phone, customer_email,
    event_type, guests, notes, price, deposit_required, event_details)
  select 'member', r, d::date, s, st, null, fn, ln, ph, em, et, g, n, pr, 100, ed || jsonb_build_object('src', 'sample-2026')
  from (values
    ('hall',   '2026-11-06', 'evening',   'confirmed', 'Chloe',   'Martin',  '07700 900301', 'chloe.martin@example.com',  '18th Birthday',     80, 'DJ booked. Buffet at 9pm.', 250, '{"celebrant":"Chloe Martin","id_checks":true,"door_notes":"Wristbands for over-18s."}'::jsonb),
    ('lounge', '2026-11-07', 'afternoon', 'confirmed', 'Sarah',   'Hughes',  '07700 900302', 'sarah.hughes@example.com',  'Christening',       35, 'Cake on arrival.', 90, '{}'::jsonb),
    ('hall',   '2026-11-13', 'evening',   'confirmed', 'Dean',    'Fletcher','07700 900303', 'dean.fletcher@example.com', 'Birthday',          90, '50th birthday. Band 8pm–11pm.', 250, '{}'::jsonb),
    ('lounge', '2026-11-19', 'evening',   'confirmed', 'Ashford', 'Allotments', '07700 900304', 'secretary@example.com', 'Meeting',          20, 'AGM. Tables in rows please.', 80, '{}'::jsonb),
    ('hall',   '2026-11-21', 'afternoon', 'confirmed', 'Margaret','Doyle',   '07700 900305', 'm.doyle@example.com',       'Wake',              60, 'Sandwiches and tea urn.', 180, '{}'::jsonb),
    ('hall',   '2026-11-27', 'evening',   'pending',   'Priya',   'Kapoor',  '07700 900306', 'priya.k@example.com',       'Engagement',       100, 'Asking about decorations from 4pm.', 250, '{}'::jsonb),
    ('lounge', '2026-11-28', 'evening',   'pending',   'Liam',    'Walsh',   '07700 900307', 'liam.walsh@example.com',    'Birthday',          40, '30th birthday.', 120, '{}'::jsonb),
    ('lounge', '2026-12-02', 'evening',   'confirmed', 'Kent',    'Darts Assoc', '07700 900308', 'kda@example.com',     'Meeting',           15, 'Committee meeting.', 80, '{}'::jsonb),
    ('hall',   '2026-12-12', 'evening',   'confirmed', 'Ellis',   'Logistics','07700 900309', 'hr@example.com',           'Club function',    110, 'Works Christmas party. Hot buffet.', 250, '{}'::jsonb),
    ('hall',   '2026-12-18', 'evening',   'confirmed', 'Jade',    'Turner',  '07700 900310', 'jade.turner@example.com',   'Wedding reception', 120, 'Evening reception. First dance 8:30pm.', 250, '{}'::jsonb),
    ('lounge', '2026-12-27', 'afternoon', 'pending',   'Brian',   'Cooke',   '07700 900311', 'b.cooke@example.com',       'Anniversary',       30, '40th wedding anniversary.', 90, '{}'::jsonb)
  ) v(r, d, s, st, fn, ln, ph, em, et, g, n, pr, ed)
  returning id, status, price
)
insert into public.payments (booking_id, amount, kind, method, paid_on, note, taken_by)
select id, least(100, price), 'deposit', 'card', current_date, 'Deposit', null from b where status = 'confirmed';

-- Check
select booking_date, case booking_kind when 'club' then 'Club event' else 'Member hire' end as kind, event_type, room, slot, status
from public.bookings where event_details->>'src' in ('poster-2026', 'sample-2026') order by booking_date, slot;
