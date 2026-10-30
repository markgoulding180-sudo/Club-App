-- Bar / door staff logins (password: railway). They start with no regular shifts; set those on the Staff page.
-- Safe to run more than once.
do $$
declare
  r record; uid uuid;
begin
  for r in select * from (values
      ('adam@railway.com',    'Adam',    'Varley',         'staff', null::text, array[]::text[]),
      ('yannika@railway.com', 'Yannika', 'Jackson',        'staff', null, array[]::text[]),
      ('heather@railway.com', 'Heather', 'Fraser Lambert', 'staff', null, array[]::text[]),
      ('luis@railway.com',    'Luis',    'Beaumont',       'staff', null, array[]::text[]),
      ('joe@railway.com',     'Joe',     'Blogs',          'staff', null, array[]::text[]),
      ('jamie@railway.com',   'Jamie',   'Preston',        'staff', null, array[]::text[]),
      ('larry@railway.com',   'Larry',   'Goldsmith',      'staff', null, array[]::text[])
    ) as t(email, first_name, last_name, role, title, perms)
  loop
    select id into uid from auth.users where lower(email) = r.email;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', r.email,
        extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
        jsonb_build_object('first_name', r.first_name, 'last_name', r.last_name), now(), now(), '', '', '', '');
      insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', r.email, 'email_verified', true), 'email', now(), now(), now());
    else
      update auth.users set encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')), email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid;
    end if;

    insert into public.profiles (id, email, first_name, last_name) values (uid, r.email, r.first_name, r.last_name)
    on conflict (id) do nothing;
    update public.profiles set first_name = r.first_name, last_name = r.last_name, email = r.email,
      role = r.role, title = r.title, perms = r.perms, skill = 'both', regular_shifts = '[]'::jsonb
    where id = uid;
  end loop;
end $$;

-- Check
select first_name, last_name, email, role, title, perms from public.profiles order by role, title, last_name;
