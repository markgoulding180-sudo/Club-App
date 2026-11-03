-- TEST: put Heather's holiday request (Wed 18 – Fri 20 Nov) back to "waiting" so it can be declined again with a message.
-- Leaves everything else (Adam's approved holiday, the rota) as it is.
delete from public.holiday_requests where staff_id = (select id from public.profiles where lower(email) = 'heather@railway.com');
insert into public.holiday_requests (staff_id, days, note, status)
select id, array[date '2026-11-18', date '2026-11-19', date '2026-11-20'], 'Trip to see my mum', 'pending'
from public.profiles where lower(email) = 'heather@railway.com';

select p.first_name, to_char(h.days[1], 'Dy DD Mon') || ' – ' || to_char(h.days[3], 'Dy DD Mon') as dates, h.note, h.status
from public.holiday_requests h join public.profiles p on p.id = h.staff_id where lower(p.email) = 'heather@railway.com';
