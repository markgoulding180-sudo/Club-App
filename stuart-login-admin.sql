-- OPTIONAL: lets Stuart keep using the login he was sent before: admin@railway.com / railway.
-- Moves Stuart's Secretary account (stuart@railway.com) to that email. His role, photo and messages stay.
-- After this, stuart@railway.com no longer works. Safe to run again.
do $$
declare uid uuid;
begin
  if exists (select 1 from auth.users where lower(email) = 'admin@railway.com') then
    raise exception 'admin@railway.com already exists. Delete it in Authentication → Users first, then run this again.';
  end if;
  select id into uid from auth.users where lower(email) = 'stuart@railway.com';
  if uid is null then raise exception 'Can''t find stuart@railway.com. Run add-secretary-stuart.sql first.'; end if;
  update auth.users set email = 'admin@railway.com', encrypted_password = extensions.crypt('railway', extensions.gen_salt('bf')) where id = uid;
  update auth.identities set identity_data = identity_data || jsonb_build_object('email', 'admin@railway.com') where user_id = uid and provider = 'email';
  update public.profiles set email = 'admin@railway.com' where id = uid;
end $$;
select first_name, last_name, email, role, title from public.profiles where lower(email) = 'admin@railway.com';
