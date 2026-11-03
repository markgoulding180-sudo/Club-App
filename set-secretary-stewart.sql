-- Stewart (stewart@railway.com) is the Secretary. Password: railway. Safe to run again.
-- If Stuart's account already exists under another email (stuart@ or stuart.fraser@railway.com),
-- that account is moved to stewart@railway.com, so his photo and messages stay with him.
do $$
declare uid uuid; old uuid;
begin
  select id into uid from auth.users where lower(email) = 'stewart@railway.com';
  select id into old from auth.users where lower(email) in ('stuart.fraser@railway.com', 'stuart@railway.com') order by created_at limit 1;

  if uid is null and old is not null then
    -- Move the existing account to the new email
    uid := old;
    update auth.users set email = 'stewart@railway.com' where id = uid;
    update auth.identities set identity_data = identity_data || jsonb_build_object('email', 'stewart@railway.com') where user_id = uid and provider = 'email';
  elsif uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'stewart@railway.com',
      extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
      jsonb_build_object('first_name', 'Stewart', 'last_name', 'Fraser'), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', 'stewart@railway.com', 'email_verified', true), 'email', now(), now(), now());
  end if;

  update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
  insert into public.profiles (id, email, first_name, last_name) values (uid, 'stewart@railway.com', 'Stewart', 'Fraser') on conflict (id) do nothing;
  update public.profiles set email = 'stewart@railway.com', first_name = 'Stewart', last_name = coalesce(nullif(last_name, ''), 'Fraser'),
    role = 'admin', title = 'Secretary', perms = array[]::text[], skill = null, regular_shifts = '[]'::jsonb
  where id = uid;

  -- Only one Secretary: any other Stuart account left over becomes a plain member
  update public.profiles set role = 'user', title = null, perms = array[]::text[]
  where id <> uid and (title ilike 'secretary' or lower(email) in ('stuart.fraser@railway.com', 'stuart@railway.com'));
end $$;

select first_name, last_name, email, role, title from public.profiles where role = 'admin' or title is not null order by title;
