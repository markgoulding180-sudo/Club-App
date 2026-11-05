-- Regular shifts for the club's real staff. Full-timers only: part-timers (Meg, Lauren, Mandy) have no regular shifts,
-- they're used for functions and extra cover (cover requests). Their old shifts went to the full-timers with the fewest.
-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat. Safe to run again.
--
--              Mon      Tue      Wed      Thu      Fri      Sat      Sun
-- AM (bar)     Sam      Adam*    -        Sam*     Lucy     Lucy     Adam
-- PM (bar)     Lucy     Sam      Adam     Lucy     Luis     Luis     Lucy
-- Door         Adam     Luis     Sam      Luis     Sam      Adam     Luis
--
-- On the rota each week: Lucy 5, Luis 5, Adam 4, Sam 4.
-- * Adam (Tue AM) and Sam (Thu AM) are saved but won't go on the rota until the app has daytime opening on Tue and Thu.

update public.profiles set regular_shifts = '[{"d":1,"s":"day","j":"lounge"},{"d":4,"s":"day","j":"lounge"},{"d":2,"s":"eve","j":"lounge"},{"d":3,"s":"eve","j":"door"},{"d":5,"s":"eve","j":"door"}]'
 where lower(email) = 'sam@railway.com';
update public.profiles set regular_shifts = '[{"d":5,"s":"day","j":"lounge"},{"d":6,"s":"day","j":"lounge"},{"d":1,"s":"eve","j":"lounge"},{"d":4,"s":"eve","j":"lounge"},{"d":0,"s":"eve","j":"lounge"}]'
 where lower(email) = 'lucy@railway.com';
update public.profiles set regular_shifts = '[{"d":2,"s":"day","j":"lounge"},{"d":0,"s":"day","j":"lounge"},{"d":3,"s":"eve","j":"lounge"},{"d":1,"s":"eve","j":"door"},{"d":6,"s":"eve","j":"door"}]'
 where lower(email) = 'adam@railway.com';
update public.profiles set regular_shifts = '[{"d":5,"s":"eve","j":"lounge"},{"d":6,"s":"eve","j":"lounge"},{"d":2,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"door"},{"d":0,"s":"eve","j":"door"}]'
 where lower(email) = 'luis@railway.com';
update public.profiles set regular_shifts = '[]', hours = 'part'
 where lower(email) in ('meg@railway.com', 'lauren@railway.com', 'mandy@railway.com');
update public.profiles set hours = 'full' where lower(email) in ('sam@railway.com', 'lucy@railway.com', 'adam@railway.com', 'luis@railway.com');

-- Check
select first_name, case hours when 'full' then 'Full time' else 'Part time' end as hours, jsonb_array_length(regular_shifts) as regular_shifts_a_week
from public.profiles where role in ('staff', 'admin') and skill is not null order by hours, regular_shifts_a_week desc, first_name;
