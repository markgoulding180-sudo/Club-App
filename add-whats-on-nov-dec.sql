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
