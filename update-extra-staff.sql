-- =====================================================================
-- Extra bar staff for club events. Run once in Club-APP:
-- SQL Editor -> New query -> paste -> Run. Safe to run more than once.
-- =====================================================================
alter table public.bookings
  add column if not exists bar_staff int check (bar_staff is null or bar_staff between 0 and 10);

-- Staff rota summaries include the extra bar staff number
drop function if exists public.get_day_summaries(date, date);
create function public.get_day_summaries(from_date date, to_date date)
returns table (booking_date date, room text, slot text, event_type text, guests int, status text, booking_name text,
               booking_kind text, start_time time, end_time time, bar_staff int)
language sql stable security definer set search_path = '' as $$
  select b.booking_date, b.room, b.slot, b.event_type, b.guests, b.status, trim(coalesce(b.first_name,'') || ' ' || coalesce(b.last_name,'')),
         b.booking_kind, b.start_time, b.end_time, b.bar_staff
  from public.bookings b
  where public.is_staff_or_admin() and b.status <> 'cancelled' and b.booking_date between from_date and to_date;
$$;
grant execute on function public.get_day_summaries(date, date) to authenticated;
