-- TEST APP ONLY (Club-APP-test): holiday requests from other staff, so Mark and Heather can test holidays.
-- All are WAITING for the manager, on the next rota (Mon 30 Nov – Sun 27 Dec), which isn't out yet.
--   Adam   Fri 4 – Sun 6 Dec   "Weekend away"
--   Luis   Sat 5 – Mon 7 Dec   "Family wedding"     -> Sat 5 and Sun 6 Dec now have 2 people asking = FULL
--   Joe    Tue 15 – Thu 17 Dec "Christmas shopping trip"
--   Larry  Sat 19 – Sun 20 Dec "Visiting my son"
-- Run test-reset-all.sql first for a clean start. Safe to run again (replaces these four).
delete from public.holiday_requests h using public.profiles p
 where h.staff_id = p.id and lower(p.email) in ('adam@railway.com','luis@railway.com','joe@railway.com','larry@railway.com');

insert into public.holiday_requests (staff_id, days, note, status, created_at)
select p.id, array(select generate_series(t.d1, t.d2, interval '1 day')::date), t.note, 'pending', now() - t.ago
from (values
  ('adam@railway.com',  date '2026-12-04', date '2026-12-06', 'Weekend away',            interval '4 hours'),
  ('luis@railway.com',  date '2026-12-05', date '2026-12-07', 'Family wedding',          interval '3 hours'),
  ('joe@railway.com',   date '2026-12-15', date '2026-12-17', 'Christmas shopping trip', interval '2 hours'),
  ('larry@railway.com', date '2026-12-19', date '2026-12-20', 'Visiting my son',         interval '1 hour')
) as t(email, d1, d2, note, ago)
join public.profiles p on lower(p.email) = t.email;

select p.first_name, h.days, h.note, h.status from public.holiday_requests h join public.profiles p on p.id = h.staff_id order by h.created_at;
