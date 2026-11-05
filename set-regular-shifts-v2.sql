-- Regular shifts for everyone, with part-timers given some regular shifts too.
-- Adds a Full time / Part time setting (Staff → tap someone → Hours), so a part-timer with regular shifts still shows as PT.
-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat. One shift a day each.
--
--              Mon        Tue        Wed        Thu        Fri        Sat        Sun
-- Bar day      Luis       -          -          -          Adam       Jamie (PT) Luis
-- Bar eve      Heather    Joe (PT)   Heather    Heather    Luis       Adam       Heather
-- Door eve     Adam       Luis       Yannika    Yannika    Yannika    Larry (PT) Larry (PT)
--
-- Full time: Luis 4, Heather 4, Adam 3, Yannika 3.  Part time: Larry 2, Joe 1, Jamie 1 (plus Function Room shifts as cover).
-- Safe to run again.

alter table public.profiles add column if not exists hours text check (hours in ('full', 'part'));

create or replace function public.admin_set_hours(pid uuid, h text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  if h not in ('full', 'part') then raise exception 'Pick full time or part time.'; end if;
  update public.profiles set hours = h where id = pid;
end $$;
grant execute on function public.admin_set_hours(uuid, text) to authenticated;

-- Full time
update public.profiles set hours = 'full', skill = 'both', regular_shifts =      -- Luis: Mon day bar, Tue door, Fri eve bar, Sun day bar
  '[{"d":1,"s":"day","j":"lounge"},{"d":2,"s":"eve","j":"door"},{"d":5,"s":"eve","j":"lounge"},{"d":0,"s":"day","j":"lounge"}]'
  where lower(email) = 'luis@railway.com';
update public.profiles set hours = 'full', skill = 'both', regular_shifts =      -- Heather: Mon, Wed, Thu, Sun eve bar
  '[{"d":1,"s":"eve","j":"lounge"},{"d":3,"s":"eve","j":"lounge"},{"d":4,"s":"eve","j":"lounge"},{"d":0,"s":"eve","j":"lounge"}]'
  where lower(email) = 'heather@railway.com';
update public.profiles set hours = 'full', skill = 'both', regular_shifts =      -- Adam: Mon door, Fri day bar, Sat eve bar
  '[{"d":1,"s":"eve","j":"door"},{"d":5,"s":"day","j":"lounge"},{"d":6,"s":"eve","j":"lounge"}]'
  where lower(email) = 'adam@railway.com';
update public.profiles set hours = 'full', skill = 'both', regular_shifts =      -- Yannika: Wed, Thu, Fri door
  '[{"d":3,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"door"},{"d":5,"s":"eve","j":"door"}]'
  where lower(email) = 'yannika@railway.com';

-- Part time: a few regular shifts, plus the days they can usually work
update public.profiles set hours = 'part', skill = 'door', avail_days = '[5,6,0]', regular_shifts =   -- Larry: Sat and Sun door
  '[{"d":6,"s":"eve","j":"door"},{"d":0,"s":"eve","j":"door"}]'
  where lower(email) = 'larry@railway.com';
update public.profiles set hours = 'part', skill = 'both', avail_days = '[2,3,4]', regular_shifts =   -- Joe: Tue eve bar
  '[{"d":2,"s":"eve","j":"lounge"}]'
  where lower(email) = 'joe@railway.com';
update public.profiles set hours = 'part', skill = 'both', avail_days = '[5,6,0]', regular_shifts =   -- Jamie: Sat day bar
  '[{"d":6,"s":"day","j":"lounge"}]'
  where lower(email) = 'jamie@railway.com';

-- Check
select first_name, case hours when 'full' then 'Full time' else 'Part time' end as hours, skill,
       jsonb_array_length(regular_shifts) as regular_shifts_a_week, avail_days as can_work_days
from public.profiles where role = 'staff' order by hours, regular_shifts_a_week desc, first_name;
