-- TEST APP ONLY: a plain member login, to test what members see (members features only, no staff or manager screens).
-- Login: member@railway.com   Password: railway   Name: Test Member
do $$
declare uid uuid; num text;
begin
  select id into uid from auth.users where lower(email) = 'member@railway.com';
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'member@railway.com',
      extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
      '{"first_name":"Test","last_name":"Member"}', now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', 'member@railway.com', 'email_verified', true), 'email', now(), now(), now());
  end if;
  insert into public.profiles (id, email, first_name, last_name) values (uid, 'member@railway.com', 'Test', 'Member') on conflict (id) do nothing;
  select coalesce(max(nullif(regexp_replace(membership_no, '\D', '', 'g'), '')::int), 0) + 1 into num from public.profiles where id <> uid;
  update public.profiles set role = 'user', title = null, perms = '{}', skill = null, regular_shifts = '[]'::jsonb,
         first_name = 'Test', last_name = 'Member', membership_no = coalesce(membership_no, num)
   where id = uid;
end $$;

select first_name, last_name, email, role, membership_no from public.profiles where lower(email) = 'member@railway.com';
