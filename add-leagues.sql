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
