-- Ashford Premier League darts: Mondays, 7pm to 11pm, Lounge Bar, 2 Nov to 14 Dec 2026 (break for Christmas like the other leagues).
-- League nights stay off the public What's On, but show in Bookings and on the rota.
-- If the Lounge Bar is already booked that evening, that Monday is skipped and listed at the end. Safe to run again.
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
select to_char(b.booking_date, 'Dy DD Mon') as monday_not_added, coalesce(b.event_type, 'booking') || ' · ' || b.first_name || ' ' || b.last_name as lounge_already_booked_for
from public.bookings b
where b.room = 'lounge' and b.status <> 'cancelled' and extract(dow from b.booking_date) = 1 and b.booking_date between '2026-11-02' and '2026-12-14'
  and b.slot in ('evening', 'full_day') and b.event_type <> 'Ashford Premier League' order by b.booking_date;
