-- TEST APP ONLY (Club-APP-test): answers every open cover request for the other staff (not Heather),
-- with a mix of yes and no, so the manager has several shifts to pick from. Safe to run again.
-- Each staff member who could work a shift answers it: about half say yes, the rest say no.
do $$
declare c record; p record; n int := 0;
begin
  for c in select * from public.cover_calls where status = 'open' order by shift_date, id loop
    for p in
      select pr.id, pr.first_name from public.profiles pr
      where pr.role = 'staff' and lower(pr.first_name) <> 'heather'
        and (coalesce(pr.skill, 'both') = 'both' or (pr.skill = 'door' and c.job = 'door') or (pr.skill = 'bar' and c.job in ('lounge', 'event')))
        and not exists (select 1 from public.shifts s where s.staff_id = pr.id and s.shift_date = c.shift_date and s.status in ('assigned', 'confirmed', 'late'))
        and not exists (select 1 from public.staff_unavailability u where u.staff_id = pr.id and u.off_date = c.shift_date)
        and not exists (select 1 from public.shift_offers o where o.staff_id = pr.id and o.shift_date = c.shift_date and o.session = c.session and o.job = c.job and o.status = 'accepted')
      order by pr.first_name
    loop
      n := n + 1;
      delete from public.shift_offers where shift_date = c.shift_date and session = c.session and job = c.job and staff_id = p.id and status in ('offered', 'passed');
      insert into public.shift_offers (shift_date, session, job, staff_id, status)
      values (c.shift_date, c.session, c.job, p.id, case when n % 2 = 1 then 'offered' else 'passed' end);
    end loop;
  end loop;
end $$;

select to_char(o.shift_date, 'Dy DD Mon') as shift, case o.job when 'event' then 'Function Room Bar' when 'door' then 'Door' else 'Lounge Bar' end as job,
       string_agg(case when o.status = 'offered' then p.first_name end, ', ') as "said YES",
       string_agg(case when o.status = 'passed' then p.first_name end, ', ') as "said no"
from public.shift_offers o join public.profiles p on p.id = o.staff_id
join public.cover_calls c on c.shift_date = o.shift_date and c.session = o.session and c.job = o.job and c.status = 'open'
where o.status in ('offered', 'passed') group by o.shift_date, o.job order by o.shift_date;
