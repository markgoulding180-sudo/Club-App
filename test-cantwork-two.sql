-- TEST APP ONLY: two staff ask off a shift (as they would in their app), Lucy first, then Luis 5 minutes later.
-- Run after update-cantwork-asked-at.sql.
update public.shifts s set status = 'cannot_work', reason = 'Dentist appointment', decision = null, decided_at = null
from public.profiles p where p.id = s.staff_id and lower(p.email) = 'lucy@railway.com' and s.shift_date = '2026-11-27' and s.job = 'lounge';
update public.shifts s set asked_off_at = now() - interval '10 minutes'
from public.profiles p where p.id = s.staff_id and lower(p.email) = 'lucy@railway.com' and s.shift_date = '2026-11-27' and s.job = 'lounge';
update public.shifts s set status = 'cannot_work', reason = 'Family wedding', decision = null, decided_at = null
from public.profiles p where p.id = s.staff_id and lower(p.email) = 'luis@railway.com' and s.shift_date = '2026-11-25' and s.job = 'door';
update public.shifts s set asked_off_at = now() - interval '5 minutes'
from public.profiles p where p.id = s.staff_id and lower(p.email) = 'luis@railway.com' and s.shift_date = '2026-11-25' and s.job = 'door';
select p.first_name, to_char(s.shift_date, 'Dy DD Mon') as day, s.job, s.reason, to_char(s.asked_off_at, 'HH24:MI') as asked
from public.shifts s join public.profiles p on p.id = s.staff_id where s.status = 'cannot_work' and s.decision is null order by s.asked_off_at;
