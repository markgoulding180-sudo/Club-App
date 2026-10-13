-- =====================================================================
-- Club events update. Run once in Club-APP: SQL Editor -> New query -> paste -> Run.
-- Safe to run on the database you already set up.
-- =====================================================================

-- New fields on bookings for club events
alter table public.bookings
  add column if not exists booking_kind text not null default 'member' check (booking_kind in ('member', 'club')),
  add column if not exists start_time   time,
  add column if not exists end_time     time,
  add column if not exists ticketed     boolean not null default false,
  add column if not exists price_member numeric(8,2),
  add column if not exists price_guest  numeric(8,2);

-- Only admins can add club events; members can only request member bookings
drop policy if exists "customers request, admins add" on public.bookings;
create policy "customers request, admins add" on public.bookings
  for insert to authenticated
  with check (public.is_admin() or (user_id = auth.uid() and status = 'pending' and booking_kind = 'member'));

-- Everyone signed in can see club events (for What's On)
drop policy if exists "everyone signed in sees club events" on public.bookings;
create policy "everyone signed in sees club events" on public.bookings
  for select to authenticated using (booking_kind = 'club' and status <> 'cancelled');

-- Staff rota summaries now include club events and their times
drop function if exists public.get_day_summaries(date, date);
create function public.get_day_summaries(from_date date, to_date date)
returns table (booking_date date, room text, slot text, event_type text, guests int, status text, booking_name text,
               booking_kind text, start_time time, end_time time)
language sql stable security definer set search_path = '' as $$
  select b.booking_date, b.room, b.slot, b.event_type, b.guests, b.status, trim(coalesce(b.first_name,'') || ' ' || coalesce(b.last_name,'')),
         b.booking_kind, b.start_time, b.end_time
  from public.bookings b
  where public.is_staff_or_admin() and b.status <> 'cancelled' and b.booking_date between from_date and to_date;
$$;
grant execute on function public.get_day_summaries(date, date) to authenticated;
