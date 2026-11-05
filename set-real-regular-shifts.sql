-- Regular shifts for the club's real staff, taken from the club's November rota (the pattern that repeats most weeks).
-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat. Every password is: railway. Safe to run again.
--
--              Mon          Tue      Wed      Thu      Fri      Sat      Sun
-- AM (bar)     Sam + Lucy   Adam*    -        Sam*     Lucy     Lucy     Adam
-- PM (bar)     Meg          Meg      Lauren   Lauren   Luis     Meg      Lucy
-- Door         Adam         Luis     Sam      Luis     Sam      Adam     Luis
--
-- * The app's opening times have no daytime on Tue, Wed or Thu, and only 1 person on the bar, so Adam (Tue AM),
--   Sam (Thu AM) and Lucy (Mon AM, 2nd person) are saved but won't be put on the rota until those are added.
-- Weeks that alternate (Mon PM Meg/Lucy, Thu PM Lauren/Meg, Sat PM Meg/Sam, Sun PM Lucy/Sam, Mon door Adam/Luis,
-- Wed door Sam/Luis, Thu door Luis/Adam, Sat door Adam/Sam/Luis, Sun door Luis/Adam, Sun AM Adam/Lucy)
-- use the first person; change them on the rota after filling. Mandy only cleans: no Clean job in the app yet.

update public.profiles set regular_shifts = '[{"d":1,"s":"day","j":"lounge"},{"d":4,"s":"day","j":"lounge"},{"d":3,"s":"eve","j":"door"},{"d":5,"s":"eve","j":"door"}]'
 where lower(email) = 'sam@railway.com';
update public.profiles set regular_shifts = '[{"d":1,"s":"day","j":"lounge"},{"d":5,"s":"day","j":"lounge"},{"d":6,"s":"day","j":"lounge"},{"d":0,"s":"eve","j":"lounge"}]'
 where lower(email) = 'lucy@railway.com';
update public.profiles set regular_shifts = '[{"d":2,"s":"day","j":"lounge"},{"d":0,"s":"day","j":"lounge"},{"d":1,"s":"eve","j":"door"},{"d":6,"s":"eve","j":"door"}]'
 where lower(email) = 'adam@railway.com';
update public.profiles set regular_shifts = '[{"d":5,"s":"eve","j":"lounge"},{"d":2,"s":"eve","j":"door"},{"d":4,"s":"eve","j":"door"},{"d":0,"s":"eve","j":"door"}]'
 where lower(email) = 'luis@railway.com';
update public.profiles set regular_shifts = '[{"d":1,"s":"eve","j":"lounge"},{"d":2,"s":"eve","j":"lounge"},{"d":6,"s":"eve","j":"lounge"}]'
 where lower(email) = 'meg@railway.com';
update public.profiles set regular_shifts = '[{"d":3,"s":"eve","j":"lounge"},{"d":4,"s":"eve","j":"lounge"}]'
 where lower(email) = 'lauren@railway.com';
update public.profiles set regular_shifts = '[]' where lower(email) = 'mandy@railway.com';

-- Check
select first_name, case hours when 'full' then 'Full time' else 'Part time' end as hours, jsonb_array_length(regular_shifts) as regular_shifts_a_week
from public.profiles where role in ('staff', 'admin') and skill is not null order by regular_shifts_a_week desc, first_name;
