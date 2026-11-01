-- RESET FOR TESTING: clears the rota and everything staff-related, so you can start fresh.
-- Clears: shifts, rota publishing, swaps (requests, offers, history), cover calls, shift offers, holiday requests,
-- unavailable days, can't-work records, staff notes, staff messages, notices, the member message board, and waiting phone notifications.
-- Keeps: every account, everyone's role and regular days, bookings, What's On, leagues, newsletter.
do $$
declare t text; list text := '';
begin
  foreach t in array array['swap_offers','swap_requests','shift_swaps','shift_offers','cover_calls','holiday_requests',
    'staff_unavailability','staff_notes','staff_messages','notice_reads','club_notices','member_messages','push_queue','push_reminded',
    'shifts','rota_periods'] loop
    if to_regclass('public.' || t) is not null then list := list || case when list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  execute 'truncate table ' || list || ' cascade';   -- ids carry on, so old "cleared" notifications on phones can't hide new ones
end $$;

select (select count(*) from public.shifts) as shifts, (select count(*) from public.shift_swaps) as swaps,
       (select count(*) from public.swap_requests) as swap_requests, (select count(*) from public.holiday_requests) as holidays,
       (select count(*) from public.club_notices) as notices, (select count(*) from public.staff_messages) as staff_messages,
       (select count(*) from public.profiles where role = 'staff') as staff_kept;
