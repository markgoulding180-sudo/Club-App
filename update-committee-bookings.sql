-- The Entertainments committee (anyone with What's On access) can book club events in the Function Room or Lounge,
-- with a room and start/finish time, from the What's On page. They can't see or change members' bookings.
-- Run after update-roles-notices-jobs.sql and update-club-priority.sql. Safe to run again.
drop policy if exists "committee books club events" on public.bookings;
create policy "committee books club events" on public.bookings for insert to authenticated
  with check (booking_kind = 'club' and public.has_perm('whatson'));
drop policy if exists "committee changes club events" on public.bookings;
create policy "committee changes club events" on public.bookings for update to authenticated
  using (booking_kind = 'club' and public.has_perm('whatson')) with check (booking_kind = 'club' and public.has_perm('whatson'));
drop policy if exists "committee removes club events" on public.bookings;
create policy "committee removes club events" on public.bookings for delete to authenticated
  using (booking_kind = 'club' and public.has_perm('whatson'));
select 'done' as result;
