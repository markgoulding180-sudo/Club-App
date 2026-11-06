-- TEST APP ONLY: answer the open cover request(s) as the staff would in their app.
-- Lucy and Lauren say "Yes, I can". Sam says "No, sorry". (Only people who could actually work it.)
do $$
declare c record; who text; p uuid; ans text; n int := 0;
begin
  for c in select * from public.cover_calls where status = 'open' and shift_date >= current_date order by shift_date loop
    foreach who in array array['lucy', 'lauren', 'sam'] loop
      select id into p from public.profiles where lower(email) = who || '@railway.com';
      continue when exists (select 1 from public.shifts x where x.staff_id = p and x.shift_date = c.shift_date
                              and ((x.status in ('assigned', 'confirmed', 'late') and (x.job = 'clean') = (c.job = 'clean'))
                                   or x.status in ('cannot_work', 'sick', 'no_show')));
      continue when exists (select 1 from public.staff_unavailability u where u.staff_id = p and u.off_date = c.shift_date);
      ans := case when who = 'sam' then 'passed' else 'offered' end;
      insert into public.shift_offers (shift_date, session, job, staff_id, status) values (c.shift_date, c.session, c.job, p, ans)
      on conflict do nothing;
      n := n + 1;
    end loop;
  end loop;
  if n = 0 then raise exception 'No open cover requests that Lucy, Lauren or Sam could answer.'; end if;
end $$;

select to_char(o.shift_date, 'Dy DD Mon') as day, o.session, o.job, p.first_name, case o.status when 'offered' then 'Yes, I can' when 'passed' then 'No, sorry' else o.status end as answer
from public.shift_offers o join public.profiles p on p.id = o.staff_id
where o.shift_date >= current_date order by o.shift_date, p.first_name;
