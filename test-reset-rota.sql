-- TEST APP ONLY (Club-APP-test): wipes the rota so you can build it again from scratch.
-- Clears: all shifts, rota publishing (every rota back to Draft), cover requests and answers, swaps,
--         holiday requests, unavailable days, can't-work records, and waiting phone notifications.
-- Keeps: every account, staff regular days, bookings, What's On, messages, notices, photos, feature switches.
do $$
declare t text; list text := '';
begin
  foreach t in array array['swap_offers','swap_requests','shift_swaps','shift_offers','cover_calls','holiday_requests',
    'staff_unavailability','push_queue','shifts','rota_periods'] loop
    if to_regclass('public.' || t) is not null then list := list || case when list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  execute 'truncate table ' || list || ' cascade';
end $$;

select (select count(*) from public.shifts) as shifts_left, (select count(*) from public.cover_calls) as cover_requests_left,
       (select count(*) from public.holiday_requests) as holiday_requests_left, (select count(*) from public.rota_periods) as published_rotas,
       (select count(*) from public.profiles where role = 'staff') as staff_kept;
