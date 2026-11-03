-- Removes every Stewart / Stuart account (login and profile), so you can start him again cleanly.
-- Their messages go with them. Safe to run again.
-- (You can also do this in Supabase: Authentication → Users → tick them → Delete. Either way is fine.)
select id, email from auth.users
where lower(email) like 'stewart%' or lower(email) like 'stuart%'
   or id in (select id from public.profiles where first_name ilike any (array['stewart', 'stuart']));

delete from auth.identities where user_id in (select id from auth.users
  where lower(email) like 'stewart%' or lower(email) like 'stuart%'
     or id in (select id from public.profiles where first_name ilike any (array['stewart', 'stuart'])));
delete from auth.users
where lower(email) like 'stewart%' or lower(email) like 'stuart%'
   or id in (select id from public.profiles where first_name ilike any (array['stewart', 'stuart']));
delete from public.profiles where first_name ilike any (array['stewart', 'stuart']) or lower(email) like 'stewart%' or lower(email) like 'stuart%';

select count(*) as stewart_accounts_left from public.profiles where first_name ilike any (array['stewart', 'stuart']);
