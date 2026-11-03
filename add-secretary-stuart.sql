-- Stuart Fraser, club Secretary. Login: stuart@railway.com  Password: railway. Safe to run again.
do $$
declare uid uuid;
begin
  select id into uid from auth.users where lower(email) = 'stuart@railway.com';
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'stuart@railway.com',
      extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
      jsonb_build_object('first_name', 'Stuart', 'last_name', 'Fraser'), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', 'stuart@railway.com', 'email_verified', true), 'email', now(), now(), now());
  else
    update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
  end if;
  insert into public.profiles (id, email, first_name, last_name) values (uid, 'stuart@railway.com', 'Stuart', 'Fraser') on conflict (id) do nothing;
  update public.profiles set email = 'stuart@railway.com', first_name = 'Stuart', last_name = 'Fraser',
    role = 'admin', title = 'Secretary', perms = array[]::text[], skill = null, regular_shifts = '[]'::jsonb
  where id = uid;
end $$;

select first_name, last_name, email, role, title from public.profiles where role = 'admin' or title is not null order by title;
