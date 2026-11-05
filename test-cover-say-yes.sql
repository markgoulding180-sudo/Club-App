-- TEST APP ONLY (Club-APP-test): one member of staff answers one open cover request.
-- Change the three lines below, then run. Safe to run again.
do $$
declare who  text := 'joe';          -- first name of the staff member
        day  date := '2026-11-13';   -- the shift date
        ans  text := 'yes';          -- 'yes' or 'no'
        c public.cover_calls; pid uuid;
begin
  select * into c from public.cover_calls where status = 'open' and shift_date = day order by id limit 1;
  if c.id is null then raise exception 'No open cover request on %.', day; end if;
  select id into pid from public.profiles where role = 'staff' and lower(first_name) = lower(who);
  if pid is null then raise exception 'No staff member called %.', who; end if;
  if exists (select 1 from public.shifts where staff_id = pid and shift_date = day and status in ('assigned', 'confirmed', 'late')) then
    raise exception '% is already working on %, so they wouldn''t be asked.', initcap(who), day; end if;
  delete from public.shift_offers where shift_date = c.shift_date and session = c.session and job = c.job and staff_id = pid and status in ('offered', 'passed');
  insert into public.shift_offers (shift_date, session, job, staff_id, status)
  values (c.shift_date, c.session, c.job, pid, case when ans = 'yes' then 'offered' else 'passed' end);
end $$;

select to_char(o.shift_date, 'Dy DD Mon') as shift, p.first_name as who,
       case o.status when 'offered' then 'said YES' when 'passed' then 'said no' when 'accepted' then 'on the rota' else o.status end as answer
from public.shift_offers o join public.profiles p on p.id = o.staff_id
where o.status in ('offered', 'passed', 'accepted') order by o.shift_date, p.first_name;
