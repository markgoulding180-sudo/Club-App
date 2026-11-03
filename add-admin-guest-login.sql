-- A shared login so anyone can look at the members' app.
-- Login: admin@railway.com   Password: railway   (a normal member account). Safe to run again.
do $$
declare uid uuid; stuart uuid;
begin
  insert into public.club_members (membership_no, first_name, last_name, tier, active) values ('99', 'Club', 'Guest', 'Full', true)
  on conflict (membership_no) do update set first_name = excluded.first_name, last_name = excluded.last_name, active = true;

  select id into uid from auth.users where lower(email) = 'admin@railway.com';
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'admin@railway.com',
      extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
      jsonb_build_object('first_name', 'Club', 'last_name', 'Guest'), now(), now(), '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', 'admin@railway.com', 'email_verified', true), 'email', now(), now(), now());
  else
    update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
  end if;
  insert into public.profiles (id, email, first_name, last_name) values (uid, 'admin@railway.com', 'Club', 'Guest') on conflict (id) do nothing;
  update public.profiles set email = 'admin@railway.com', first_name = 'Club', last_name = 'Guest', membership_no = '99',
    role = 'user', title = null, perms = '{}', skill = null where id = uid;

  -- A welcome message from the Secretary, so the message board has something in it
  select id into stuart from public.profiles where lower(email) = 'stuart@railway.com';
  if stuart is not null and not exists (select 1 from public.member_messages where recipient = uid and sender = stuart) then
    insert into public.member_messages (sender, recipient, body, subject)
    values (stuart, uid, 'Welcome to the new club app! Have a look round: What''s On, tickets, room hire and the newsletter. You can reply to this message too. Stuart, Secretary', 'Welcome to the club app');
  end if;
end $$;

select email, first_name, last_name, role, membership_no from public.profiles where lower(email) = 'admin@railway.com';
