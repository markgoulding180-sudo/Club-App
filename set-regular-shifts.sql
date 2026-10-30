-- Regular shifts: 4 full-timers (Adam, Larry, Sam, Stu), everyone else part-time (no regular days, added when needed).
-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat. Each full-timer has at least 2 days off a week.
-- Together they cover every regular shift: Lounge Bar every evening and every daytime the club opens (Fri, Sat, Sun, Mon), Door every evening.
update public.profiles set regular_shifts = '[]'::jsonb where role in ('staff', 'admin');

update public.profiles set skill = 'door', regular_shifts =      -- Stu: Door, Wed–Sun evenings (off Mon, Tue)
  '[{"d":3,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"door"},{"d":5,"s":"eve","j":"door"},{"d":6,"s":"eve","j":"door"},{"d":0,"s":"eve","j":"door"}]'
  where email = 'stu@arcstaff.test';
update public.profiles set skill = 'both', regular_shifts =      -- Larry: Mon day bar, Tue eve door, Thu eve bar, Sat day bar, Sun eve bar (off Wed, Fri)
  '[{"d":1,"s":"day","j":"lounge"},{"d":2,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"lounge"},{"d":6,"s":"day","j":"lounge"},{"d":0,"s":"eve","j":"lounge"}]'
  where email = 'larry@arcstaff.test';
update public.profiles set skill = 'both', regular_shifts =      -- Adam: Mon eve door, Wed eve bar, Fri day bar, Sun day bar (off Tue, Thu, Sat)
  '[{"d":1,"s":"eve","j":"door"},{"d":3,"s":"eve","j":"lounge"},{"d":5,"s":"day","j":"lounge"},{"d":0,"s":"day","j":"lounge"}]'
  where email = 'adam@arcstaff.test';
update public.profiles set skill = 'bar', regular_shifts =       -- Sam: Mon, Tue, Fri, Sat evenings on the bar (off Wed, Thu, Sun)
  '[{"d":1,"s":"eve","j":"lounge"},{"d":2,"s":"eve","j":"lounge"},{"d":5,"s":"eve","j":"lounge"},{"d":6,"s":"eve","j":"lounge"}]'
  where email = 'sam@arcstaff.test';

-- Check
select first_name, skill, jsonb_array_length(regular_shifts) as days_a_week from public.profiles
where role in ('staff', 'admin') and skill is not null order by days_a_week desc, first_name;
