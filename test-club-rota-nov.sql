-- TEST APP ONLY (Club-APP-test): the club's own November rota (Mon 2 – Sun 29 Nov 2026), exactly as they sent it.
-- Run after update-clean-job.sql. It replaces any shifts on this rota, then publishes it.
--   CLEAN -> Cleaning (08:00–11:00)    AM -> Lounge Bar daytime    PM -> Lounge Bar evening
--   DOOR  -> Door                      D/H -> Function Room Bar (with its start time)
--   A/L   -> Mandy's holiday, Wed 18 – Mon 23 Nov (approved)
-- "overnight" clean on Sat 21 and Sun 22 has no name, so those show as needing someone. So does Sat 21 door (empty on their rota).

update public.profiles set skill = 'clean', hours = 'full' where lower(email) = 'mandy@railway.com';

delete from public.cover_calls where shift_date between '2026-11-02' and '2026-11-29';
delete from public.shift_offers where shift_date between '2026-11-02' and '2026-11-29';
delete from public.shifts where shift_date between '2026-11-02' and '2026-11-29';
delete from public.staff_unavailability where off_date between '2026-11-02' and '2026-11-29';
delete from public.holiday_requests h using public.profiles p where h.staff_id = p.id and lower(p.email) = 'mandy@railway.com';

insert into public.shifts (shift_date, session, job, staff_id, start_early)
select r.d::date, r.sess, r.job, p.id, r.t::time
from (values
  -- week 1
  ('2026-11-02','day','clean','mandy',null), ('2026-11-02','day','lounge','sam',null), ('2026-11-02','day','lounge','lucy',null), ('2026-11-02','eve','lounge','meg',null), ('2026-11-02','eve','door','adam',null),
  ('2026-11-03','day','clean','sam',null),   ('2026-11-03','day','lounge','adam',null), ('2026-11-03','eve','lounge','meg',null),   ('2026-11-03','eve','door','luis',null),
  ('2026-11-04','day','clean','mandy',null), ('2026-11-04','day','lounge','adam','10:00'), ('2026-11-04','eve','lounge','lauren',null), ('2026-11-04','eve','door','sam',null),
  ('2026-11-05','day','clean','mandy',null), ('2026-11-05','day','lounge','sam',null),  ('2026-11-05','eve','lounge','lauren',null), ('2026-11-05','eve','door','luis',null),
  ('2026-11-06','day','clean','sam',null),   ('2026-11-06','day','lounge','lucy',null), ('2026-11-06','eve','lounge','luis',null),   ('2026-11-06','eve','door','adam',null),
  ('2026-11-07','day','clean','mandy',null), ('2026-11-07','day','lounge','lucy',null), ('2026-11-07','eve','lounge','meg',null),    ('2026-11-07','eve','door','luis',null),
     ('2026-11-07','eve','event','adam','18:30'), ('2026-11-07','eve','event','lauren','18:30'),
  ('2026-11-08','day','clean','mandy',null), ('2026-11-08','day','lounge','adam',null), ('2026-11-08','eve','lounge','lucy',null),   ('2026-11-08','eve','door','luis','15:00'),
  -- week 2
  ('2026-11-09','day','clean','mandy',null), ('2026-11-09','day','lounge','sam',null), ('2026-11-09','day','lounge','adam',null), ('2026-11-09','eve','lounge','lucy',null), ('2026-11-09','eve','door','luis',null),
  ('2026-11-10','day','clean','sam',null),   ('2026-11-10','day','lounge','adam',null), ('2026-11-10','eve','lounge','meg',null),   ('2026-11-10','eve','door','luis',null),
  ('2026-11-11','day','clean','mandy',null), ('2026-11-11','eve','lounge','lauren',null), ('2026-11-11','eve','door','luis',null),
  ('2026-11-12','day','clean','mandy',null), ('2026-11-12','day','lounge','sam',null),  ('2026-11-12','eve','lounge','meg',null),    ('2026-11-12','eve','door','adam',null),
     ('2026-11-12','eve','event','lauren','17:30'),
  ('2026-11-13','day','clean','sam',null),   ('2026-11-13','day','lounge','lucy',null), ('2026-11-13','eve','lounge','adam',null),   ('2026-11-13','eve','door','sam',null),
  ('2026-11-14','day','clean','mandy',null), ('2026-11-14','day','lounge','lucy',null), ('2026-11-14','eve','lounge','sam',null),    ('2026-11-14','eve','door','luis',null),
     ('2026-11-14','eve','event','meg','19:00'), ('2026-11-14','eve','event','lauren','19:00'),
  ('2026-11-15','day','clean','mandy',null), ('2026-11-15','day','lounge','lucy',null), ('2026-11-15','eve','lounge','sam',null),    ('2026-11-15','eve','door','adam',null),
  -- week 3
  ('2026-11-16','day','clean','mandy',null), ('2026-11-16','day','lounge','sam',null), ('2026-11-16','day','lounge','lucy',null), ('2026-11-16','eve','lounge','meg',null), ('2026-11-16','eve','door','adam',null),
  ('2026-11-17','day','clean','sam',null),   ('2026-11-17','day','lounge','adam',null), ('2026-11-17','eve','lounge','meg',null),   ('2026-11-17','eve','door','luis',null),
  ('2026-11-18','day','clean','sam',null),   ('2026-11-18','eve','lounge','lauren',null), ('2026-11-18','eve','door','sam',null),
  ('2026-11-19','day','clean','sam',null),   ('2026-11-19','day','lounge','sam',null),  ('2026-11-19','eve','lounge','lauren',null), ('2026-11-19','eve','door','luis',null),
  ('2026-11-20','day','clean','sam',null),   ('2026-11-20','day','lounge','lucy',null), ('2026-11-20','eve','lounge','luis',null),   ('2026-11-20','eve','door','adam',null),
  ('2026-11-21','day','lounge','lucy',null), ('2026-11-21','eve','lounge','meg',null),  ('2026-11-21','eve','event','adam','17:30'),
  ('2026-11-22','day','lounge','adam',null), ('2026-11-22','eve','lounge','lucy',null), ('2026-11-22','eve','door','luis','15:00'),
  -- week 4
  ('2026-11-23','day','clean','adam',null),  ('2026-11-23','day','lounge','sam',null), ('2026-11-23','day','lounge','adam',null), ('2026-11-23','eve','lounge','lucy',null), ('2026-11-23','eve','door','luis',null),
  ('2026-11-24','day','clean','sam',null),   ('2026-11-24','day','lounge','adam',null), ('2026-11-24','eve','lounge','meg',null),   ('2026-11-24','eve','door','luis',null),
  ('2026-11-25','day','clean','mandy',null), ('2026-11-25','eve','lounge','lauren',null), ('2026-11-25','eve','door','luis',null),
  ('2026-11-26','day','clean','mandy',null), ('2026-11-26','day','lounge','sam',null),  ('2026-11-26','eve','lounge','meg',null),    ('2026-11-26','eve','door','adam',null),
  ('2026-11-27','day','clean','sam',null),   ('2026-11-27','day','lounge','lucy',null), ('2026-11-27','eve','lounge','adam',null),   ('2026-11-27','eve','door','sam',null),
     ('2026-11-27','eve','event','luis','18:30'), ('2026-11-27','eve','event','lauren','18:30'),
  ('2026-11-28','day','clean','mandy',null), ('2026-11-28','day','lounge','lucy',null), ('2026-11-28','eve','lounge','sam',null),    ('2026-11-28','eve','door','adam',null),
     ('2026-11-28','eve','event','meg','18:30'), ('2026-11-28','eve','event','lauren','18:30'),
  ('2026-11-29','day','clean','mandy',null), ('2026-11-29','day','lounge','lucy',null), ('2026-11-29','eve','lounge','sam',null),    ('2026-11-29','eve','door','adam',null)
) as r(d, sess, job, who, t)
join public.profiles p on lower(p.email) = r.who || '@railway.com';

-- Mandy's annual leave (A/L): Wed 18 – Mon 23 Nov, approved
insert into public.holiday_requests (staff_id, days, note, status, decided_at)
select id, array(select generate_series(date '2026-11-18', date '2026-11-23', interval '1 day')::date), 'Annual leave', 'approved', now()
from public.profiles where lower(email) = 'mandy@railway.com';
insert into public.staff_unavailability (staff_id, off_date, reason, holiday_id)
select h.staff_id, d, 'Holiday', h.id from public.holiday_requests h, unnest(h.days) d
join public.profiles p on true where p.id = h.staff_id and lower(p.email) = 'mandy@railway.com'
on conflict (staff_id, off_date) do nothing;

-- Publish the November rota
insert into public.rota_periods (start_date, published_at) values ('2026-11-02', now())
on conflict (start_date) do update set published_at = now();

-- Check: shifts per person on this rota
select p.first_name, count(*) filter (where s.job <> 'clean') as bar_door_function, count(*) filter (where s.job = 'clean') as cleaning
from public.shifts s join public.profiles p on p.id = s.staff_id
where s.shift_date between '2026-11-02' and '2026-11-29' group by p.first_name order by p.first_name;
