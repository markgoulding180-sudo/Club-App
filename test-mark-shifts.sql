-- Put Mark on 8 shifts in the 2 Nov – 29 Nov rota, taking them over from other staff (not Staff Member)
with mark as (select id from public.profiles where email = 'mark@railway.com'),
skip as (select id from public.profiles where email in ('mark@railway.com', 'staff@railway.com')),
cand as (
  select s.id, s.shift_date, s.session, s.job, s.staff_id,
         row_number() over (partition by s.shift_date order by s.session desc, md5(s.id::text)) as rn
  from public.shifts s
  where s.shift_date between greatest(current_date + 1, date '2026-11-02') and date '2026-11-29'
    and s.status in ('assigned', 'confirmed') and not s.covered
    and s.staff_id not in (select id from skip)
    and extract(isodow from s.shift_date) in (2, 4, 5, 6)               -- Tue, Thu, Fri, Sat
    and not exists (select 1 from public.shift_swaps w where w.status in ('asked', 'accepted') and s.id in (w.from_shift, w.to_shift))
    and not exists (select 1 from public.swap_requests r where r.status = 'open' and r.shift_id = s.id)
    and not exists (select 1 from public.swap_offers o where o.status = 'offered' and o.shift_id = s.id)
    and not exists (select 1 from public.shifts x where x.staff_id = (select id from mark) and x.shift_date = s.shift_date and x.status in ('assigned', 'confirmed', 'late'))
),
pick as (select * from cand where rn = 1 order by shift_date limit 8),
moved as (update public.shifts s set staff_id = (select id from mark) from pick where s.id = pick.id returning s.id)
select to_char(p.shift_date, 'Dy DD Mon') as day, case p.session when 'day' then 'Daytime' else 'Evening' end as session,
       case p.job when 'lounge' then 'Lounge Bar' when 'event' then 'Function Room Bar' else 'Door' end as job,
       coalesce(pr.first_name, '') as was
from pick p join moved m on m.id = p.id left join public.profiles pr on pr.id = p.staff_id
order by p.shift_date;
