-- TEST: holiday requests from Adam, waiting for the manager.
-- Two in the next rota (30 Nov – 27 Dec) and one in the rota after (28 Dec – 24 Jan). Safe to run again.
delete from public.holiday_requests where staff_id = (select id from public.profiles where lower(email) = 'adam@railway.com') and note like 'TEST:%';
insert into public.holiday_requests (staff_id, days, note, status)
select p.id, d.days, d.note, 'pending'
from public.profiles p cross join (values
  (array[date '2026-12-04', date '2026-12-05', date '2026-12-06'], 'TEST: Long weekend away'),
  (array[date '2026-12-21', date '2026-12-22', date '2026-12-23'], 'TEST: Christmas shopping trip'),
  (array[date '2027-01-08', date '2027-01-09'], 'TEST: Friend''s wedding')
) as d(days, note)
where lower(p.email) = 'adam@railway.com';

select to_char(days[1], 'Dy DD Mon') || ' – ' || to_char(days[array_length(days, 1)], 'Dy DD Mon') as dates,
       array_length(days, 1) as days, replace(note, 'TEST: ', '') as note, status
from public.holiday_requests where note like 'TEST:%' order by days[1];
