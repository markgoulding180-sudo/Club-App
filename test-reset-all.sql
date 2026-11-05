-- TEST APP ONLY (Club-APP-test). A clean start for testing.
-- Clears: all shifts and rota publishing, cover requests, swaps, ALL holiday requests, unavailable days,
--         can't-work records, staff notes, to-do list, and ALL messages and notifications.
-- Keeps:  every account and staff regular days, bookings, What's On, events, tickets, newsletter, jobs, photos, feature switches.
-- After running: sign out and in again (or Ctrl + Shift + R) so the bell is clean too.
do $$
declare t text; list text := '';
begin
  foreach t in array array['swap_offers','swap_requests','shift_swaps','shift_offers','cover_calls','holiday_requests',
    'staff_unavailability','staff_notes','todos','push_queue','push_reminded','notice_reads','club_notices','staff_messages',
    'member_messages','hidden_messages','shifts','rota_periods'] loop
    if to_regclass('public.' || t) is not null then list := list || case when list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  execute 'truncate table ' || list || ' cascade';
end $$;

select (select count(*) from public.shifts) as shifts, (select count(*) from public.rota_periods) as published_rotas,
       (select count(*) from public.holiday_requests) as holiday_requests, (select count(*) from public.cover_calls) as cover_requests,
       (select count(*) from public.club_notices) + (select count(*) from public.staff_messages) + (select count(*) from public.member_messages) as messages,
       (select count(*) from public.bookings) as bookings_kept, (select count(*) from public.profiles where role = 'staff') as staff_kept;
