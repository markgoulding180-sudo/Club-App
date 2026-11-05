-- TEST APP ONLY (Club-APP-test): swap the made-up staff for the club's real staff.
-- Removes: Heather, Yannika, Joe, Jamie, Larry (their logins too).
-- Keeps:   Adam, Luis. Sam (Bar Manager) is put on the rota as well, as he works shifts.
-- Adds:    Mandy, Lucy, Meg, Lauren. Every password is: railway
-- Also clears the rota, holidays, swaps, cover and messages first (like test-reset-all.sql), so nothing points at the old staff.
-- Full time / part time is a first guess from the club's rota; change it in the app (Staff → tap someone → Hours).

-- 1. Clean start
do $$
declare t text; list text := '';
begin
  foreach t in array array['swap_offers','swap_requests','shift_swaps','shift_offers','cover_calls','holiday_requests',
    'staff_unavailability','staff_notes','todos','push_queue','push_reminded','notice_reads','club_notices','staff_messages',
    'member_messages','hidden_messages','shifts','rota_periods'] loop
    if to_regclass('public.' || t) is not null then list := list || case when list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  execute 'truncate table ' || list || ' cascade';
end $$;

-- 2. Remove the made-up staff
create temp table gone as select id from auth.users where lower(email) in ('heather@railway.com','yannika@railway.com','joe@railway.com','jamie@railway.com','larry@railway.com');
delete from public.profiles where id in (select id from gone);
delete from auth.identities where user_id in (select id from gone);
delete from auth.users where id in (select id from gone);
drop table gone;

-- 3. Add the real staff (logins, password: railway)
do $$
declare r record; uid uuid;
begin
  for r in select * from (values
      ('mandy@railway.com',  'Mandy',  'part'),
      ('lucy@railway.com',   'Lucy',   'full'),
      ('meg@railway.com',    'Meg',    'part'),
      ('lauren@railway.com', 'Lauren', 'part')
    ) as t(email, first_name, hours)
  loop
    select id into uid from auth.users where lower(email) = r.email;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', r.email,
        extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
        jsonb_build_object('first_name', r.first_name, 'last_name', ''), now(), now(), '', '', '', '');
      insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', r.email, 'email_verified', true), 'email', now(), now(), now());
    end if;
    insert into public.profiles (id, email, first_name, last_name) values (uid, r.email, r.first_name, '') on conflict (id) do nothing;
    update public.profiles set first_name = r.first_name, last_name = '', email = r.email, role = 'staff', title = null, perms = '{}',
      skill = 'both', hours = r.hours, regular_shifts = '[]'::jsonb where id = uid;
  end loop;
end $$;

-- 4. Adam, Luis and Sam: on the rota, full time, no regular shifts yet
update public.profiles set skill = 'both', hours = 'full', regular_shifts = '[]'::jsonb, avail_days = '[]'::jsonb
 where lower(email) in ('adam@railway.com', 'luis@railway.com', 'sam@railway.com');

-- Check: who is on the rota now
select first_name, last_name, email, role, coalesce(title, '') as title, case hours when 'full' then 'Full time' else 'Part time' end as hours
from public.profiles where role in ('staff', 'admin') and skill is not null order by first_name;
