-- FRESH ROTA: puts everyone on their regular shifts for the 4-week rota 2 Nov – 29 Nov 2026 and publishes it,
-- the same as the manager pressing "Fill from regular shifts" then "Publish". Run after reset-rota-for-testing.sql.
insert into public.shifts (shift_date, session, job, staff_id)
select d::date, e->>'s', e->>'j', p.id
from public.profiles p
cross join jsonb_array_elements(p.regular_shifts) e
cross join generate_series(date '2026-11-02', date '2026-11-29', interval '1 day') d
where p.role in ('staff', 'admin') and jsonb_array_length(p.regular_shifts) > 0
  and extract(dow from d)::int = (e->>'d')::int
  and d::date > current_date
on conflict do nothing;

insert into public.rota_periods (start_date, published_at) values ('2026-11-02', now())
on conflict (start_date) do update set published_at = now();

-- Check: shifts per person
select p.first_name, count(s.id) as shifts, min(s.shift_date) as first, max(s.shift_date) as last
from public.profiles p left join public.shifts s on s.staff_id = p.id
where p.role = 'staff' group by p.first_name order by shifts desc, p.first_name;
