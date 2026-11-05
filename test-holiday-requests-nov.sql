-- TEST APP ONLY (Club-APP-test): holiday requests from other staff, so Mark and Heather can test holidays.
-- All are WAITING for the manager, on the rota we're testing (Mon 2 – Sun 29 Nov), which isn't out yet.
--   Adam   Fri 20 – Sun 22 Nov   "Weekend away"
--   Luis   Sat 21 – Mon 23 Nov   "Family wedding"     -> Sat 21 and Sun 22 Nov now have 2 people asking = FULL
--   Joe    Tue 10 – Thu 12 Nov "Christmas shopping trip"
--   Larry  Sat 14 – Sun 15 Nov "Visiting my son"
-- Run test-reset-all.sql first for a clean start. Safe to run again (replaces these four).
delete from public.holiday_requests h using public.profiles p
 where h.staff_id = p.id and lower(p.email) in ('adam@railway.com','luis@railway.com','joe@railway.com','larry@railway.com');

insert into public.holiday_requests (staff_id, days, note, status, created_at)
select p.id, array(select generate_series(t.d1, t.d2, interval '1 day')::date), t.note, 'pending', now() - t.ago
from (values
  ('adam@railway.com',  date '2026-11-20', date '2026-11-22', 'Weekend away',            interval '4 hours'),
  ('luis@railway.com',  date '2026-11-21', date '2026-11-23', 'Family wedding',          interval '3 hours'),
  ('joe@railway.com',   date '2026-11-10', date '2026-11-12', 'Christmas shopping trip', interval '2 hours'),
  ('larry@railway.com', date '2026-11-14', date '2026-11-15', 'Visiting my son',         interval '1 hour')
) as t(email, d1, d2, note, ago)
join public.profiles p on lower(p.email) = t.email;

select p.first_name, h.days, h.note, h.status from public.holiday_requests h join public.profiles p on p.id = h.staff_id order by h.created_at;
