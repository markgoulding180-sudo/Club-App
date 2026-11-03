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


-- Holiday requests waiting for the manager, all in THIS rota (2 – 29 Nov 2026)
insert into public.holiday_requests (staff_id, days, note, status)
select p.id, d.days, d.note, 'pending'
from (values
  ('adam@railway.com',    array[date '2026-11-13', date '2026-11-14'],                    'Long weekend away'),
  ('adam@railway.com',    array[date '2026-11-23', date '2026-11-24'],                    'Dentist and family visit'),
  ('heather@railway.com', array[date '2026-11-18', date '2026-11-19', date '2026-11-20'], 'Trip to see my mum')
) as d(email, days, note)
join public.profiles p on lower(p.email) = d.email;

-- Check: rota empty, 3 holiday requests waiting
select (select count(*) from public.shifts) as shifts, (select count(*) from public.rota_periods) as rotas_published,
       (select count(*) from public.holiday_requests where status = 'pending') as holiday_requests_waiting;
select p.first_name, to_char(h.days[1], 'Dy DD Mon') || ' – ' || to_char(h.days[array_length(h.days, 1)], 'Dy DD Mon') as dates, h.note
from public.holiday_requests h join public.profiles p on p.id = h.staff_id order by h.days[1];
