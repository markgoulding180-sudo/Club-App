-- TEST APP ONLY: make sure the real staff are set up as staff (not members). Sam stays Bar Manager.
update public.profiles set role = 'staff', title = null
 where lower(email) in ('adam@railway.com','luis@railway.com','lucy@railway.com','meg@railway.com','lauren@railway.com','mandy@railway.com');
update public.profiles set skill = coalesce(skill, 'both')
 where lower(email) in ('adam@railway.com','luis@railway.com','lucy@railway.com','meg@railway.com','lauren@railway.com');

select first_name, email, role, coalesce(title, '') as title, skill,
       case hours when 'full' then 'Full time' when 'part' then 'Part time' else '' end as hours
from public.profiles
where lower(email) in ('adam@railway.com','luis@railway.com','lucy@railway.com','meg@railway.com','lauren@railway.com','mandy@railway.com','sam@railway.com')
order by first_name;
