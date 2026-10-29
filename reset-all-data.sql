-- RESET: clears all shifts, rotas, swaps, holidays, staff records, What's On, bookings (hall, club events, sports),
-- payments, tickets and no-bookings days. Keeps every account (staff, admins, members) and their logins.
do $$
declare t text; list text := '';
begin
  foreach t in array array['shift_swaps','swap_offers','swap_requests','shift_offers','shifts','staff_unavailability',
    'holiday_requests','staff_notes','rota_periods','ticket_reservations','payments','bookings','events','closed_days'] loop
    if to_regclass('public.' || t) is not null then list := list || case when list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  execute 'truncate table ' || list || ' restart identity';
end $$;

-- Staff stay as staff, but start fresh: no regular shifts set
update public.profiles set regular_shifts = '[]'::jsonb where regular_shifts is distinct from '[]'::jsonb;

-- Check: everything below should be 0
select (select count(*) from public.shifts) as shifts, (select count(*) from public.holiday_requests) as holidays,
       (select count(*) from public.bookings) as bookings, (select count(*) from public.events) as whats_on,
       (select count(*) from public.profiles where role = 'staff') as staff_kept;
