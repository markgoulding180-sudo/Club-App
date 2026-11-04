-- TEST APP ONLY (Club-APP-test): Test A, only Heather says yes. Joe and Jamie say no.
-- Mark and Heather. Change the names below to test different cases. Safe to run again.
--   say_yes: staff who say "Yes, I can"     say_no: staff who say "No, sorry"
do $$
declare say_yes text[] := array[]::text[];          -- e.g. array['joe'] for two yeses (with Heather), or array[]::text[] for none
        say_no  text[] := array['joe', 'jamie']; -- staff who say no
        c record; p record;
begin
  for c in select * from public.cover_calls where status = 'open' loop
    for p in select id, lower(first_name) as fn from public.profiles where role = 'staff' and lower(first_name) = any (say_yes || say_no) loop
      delete from public.shift_offers where shift_date = c.shift_date and session = c.session and job = c.job and staff_id = p.id and status in ('offered', 'passed');
      insert into public.shift_offers (shift_date, session, job, staff_id, status)
      values (c.shift_date, c.session, c.job, p.id, case when p.fn = any (say_yes) then 'offered' else 'passed' end);
    end loop;
  end loop;
end $$;

select to_char(o.shift_date, 'Dy DD Mon') as shift, o.job, p.first_name as who,
       case o.status when 'offered' then 'said YES' when 'passed' then 'said no' else o.status end as answer
from public.shift_offers o join public.profiles p on p.id = o.staff_id
where o.status in ('offered', 'passed') order by o.shift_date, o.status, p.first_name;
