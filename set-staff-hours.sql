-- Full time: Adam, Luis, Yannika, Heather (regular weekly shifts, at least 2 days off each).
-- Part time: Joe, Jamie, Larry (no regular shifts, used as and when).
-- Door only: Larry. Yannika works bar and door.
-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat.
-- Between them the full-timers cover every regular shift: Lounge Bar every evening, Lounge Bar daytime Fri/Sat/Sun/Mon, Door every evening.

update public.profiles set skill = 'both', regular_shifts =      -- Yannika: Door, Wed to Sun evenings (off Mon, Tue)
  '[{"d":3,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"door"},{"d":5,"s":"eve","j":"door"},{"d":6,"s":"eve","j":"door"},{"d":0,"s":"eve","j":"door"}]'
  where lower(email) = 'yannika@railway.com';
update public.profiles set skill = 'both', regular_shifts =      -- Luis: Mon day bar, Tue eve door, Thu eve bar, Fri eve bar, Sun day bar (off Wed, Sat)
  '[{"d":1,"s":"day","j":"lounge"},{"d":2,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"lounge"},{"d":5,"s":"eve","j":"lounge"},{"d":0,"s":"day","j":"lounge"}]'
  where lower(email) = 'luis@railway.com';
update public.profiles set skill = 'both', regular_shifts =      -- Adam: Mon eve door, Tue eve bar, Fri day bar, Sat eve bar (off Wed, Thu, Sun)
  '[{"d":1,"s":"eve","j":"door"},{"d":2,"s":"eve","j":"lounge"},{"d":5,"s":"day","j":"lounge"},{"d":6,"s":"eve","j":"lounge"}]'
  where lower(email) = 'adam@railway.com';
update public.profiles set skill = 'both', regular_shifts =      -- Heather: Mon eve bar, Wed eve bar, Sat day bar, Sun eve bar (off Tue, Thu, Fri)
  '[{"d":1,"s":"eve","j":"lounge"},{"d":3,"s":"eve","j":"lounge"},{"d":6,"s":"day","j":"lounge"},{"d":0,"s":"eve","j":"lounge"}]'
  where lower(email) = 'heather@railway.com';

-- Part time
update public.profiles set skill = 'door', regular_shifts = '[]'::jsonb where lower(email) = 'larry@railway.com';
update public.profiles set skill = 'both', regular_shifts = '[]'::jsonb where lower(email) in ('joe@railway.com', 'jamie@railway.com');

-- Check
select first_name, last_name, case when jsonb_array_length(regular_shifts) > 0 then 'Full time' else 'Part time' end as hours,
       skill, jsonb_array_length(regular_shifts) as shifts_a_week
from public.profiles where role = 'staff' order by hours, first_name;
