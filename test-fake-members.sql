-- TEST DATA: 200 made-up club members in the register, 12 of them with app logins
-- (password: railway), some friendships, favourite nights and Going/Interested on upcoming events.
-- All test logins use emails ending @members.test. Run after update-friends-going.sql.
-- To remove it all later, run the block at the bottom.
do $$
declare
  fn text[] := array['Jack','Oliver','Harry','George','Noah','Charlie','Jacob','Alfie','Freddie','Oscar','Leo','Archie','Thomas','James','William','Joshua','Daniel','Ethan','Samuel','Joseph',
                     'Olivia','Amelia','Isla','Ava','Emily','Sophie','Grace','Lily','Mia','Ella','Ruby','Chloe','Evie','Jessica','Poppy','Hannah','Lucy','Megan','Charlotte','Holly',
                     'Gary','Steve','Paul','Mark','Tony','Kevin','Dave','Ian','Colin','Barry','Sue','Karen','Tracey','Julie','Debbie','Linda','Carol','Janet','Wendy','Pauline'];
  ln text[] := array['Smith','Jones','Taylor','Brown','Williams','Wilson','Johnson','Davies','Robinson','Wright','Thompson','Evans','Walker','White','Roberts','Green','Hall','Wood','Jackson','Clarke',
                     'Harris','Lewis','Martin','Cooper','King','Baker','Turner','Hill','Ward','Morris','Moore','Clark','Lee','Hughes','Edwards','Bennett','Shaw','Cook','Parker','Mills'];
  tiers text[] := array['Full','Full','Full','Full','Senior','Senior','Family','Associate'];
  cats text[] := array['darts','pool','quiz','bingo','dond','music','karaoke','sport'];
  drinks text[] := array['Lager','Bitter / real ale','Cider','Stout','Wine','Prosecco','Spirits','Soft drinks'];
  i int; no text; f text; l text; uid uuid; ids uuid[] := '{}'; ev record; k int;
begin
  -- 1) The register
  for i in 1..200 loop
    no := 'ARC-' || (1000 + i);
    f := fn[1 + ((i * 7) % array_length(fn, 1))]; l := ln[1 + ((i * 13) % array_length(ln, 1))];
    insert into public.club_members (membership_no, first_name, last_name, tier, active)
    values (no, f, l, tiers[1 + (i % array_length(tiers, 1))], true)
    on conflict (membership_no) do update set first_name = excluded.first_name, last_name = excluded.last_name, tier = excluded.tier;
  end loop;

  -- 2) App logins for the first 12 (email firstname.surname@members.test, password railway)
  for i in 1..12 loop
    no := 'ARC-' || (1000 + i);
    select first_name, last_name into f, l from public.club_members where membership_no = no;
    select id into uid from auth.users where email = lower(f || '.' || l || '@members.test');
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', lower(f || '.' || l || '@members.test'),
        extensions.crypt('railway', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
        jsonb_build_object('first_name', f, 'last_name', l), now(), now(), '', '', '', '');
      insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', lower(f || '.' || l || '@members.test'), 'email_verified', true), 'email', now(), now(), now());
    end if;
    update public.profiles set first_name = f, last_name = l, membership_no = no, role = 'user', skill = null,
      prefs = jsonb_build_object('cats', jsonb_build_array(cats[1 + (i % 8)], cats[1 + ((i * 3) % 8)]), 'drinks', jsonb_build_array(drinks[1 + (i % 8)]), 'team', '', 'offers', true)
    where id = uid;
    ids := ids || uid;
  end loop;

  -- 3) Friendships between them (each with the next two), some still waiting to be accepted
  for i in 1..12 loop
    for k in 1..2 loop
      if i + k <= 12 then
        insert into public.friendships (requester, addressee, status, likes)
        values (ids[i], ids[i + k], case when (i + k) % 4 = 0 then 'pending' else 'accepted' end, array[cats[1 + (i % 8)]])
        on conflict do nothing;
      end if;
    end loop;
  end loop;

  -- 4) Going / Interested on upcoming club events
  i := 0;
  for ev in select id, booking_date from public.bookings where booking_kind = 'club' and status <> 'cancelled' and booking_date >= current_date order by booking_date limit 20 loop
    i := i + 1;
    for k in 1..12 loop
      if (k + i) % 3 <> 0 then
        insert into public.event_rsvps (user_id, event_key, event_date, status)
        values (ids[k], 'b' || ev.id, ev.booking_date, case when (k * i) % 2 = 0 then 'going' else 'interested' end)
        on conflict (user_id, event_key) do nothing;
      end if;
    end loop;
  end loop;
end $$;

-- Check
select (select count(*) from public.club_members where membership_no between 'ARC-1001' and 'ARC-1200') as register,
       (select count(*) from public.profiles where email like '%@members.test') as app_logins,
       (select count(*) from public.friendships) as friendships,
       (select count(*) from public.event_rsvps) as going_or_interested;
select first_name, last_name, membership_no, email from public.profiles where email like '%@members.test' order by membership_no;

/* ---------- TO REMOVE THE TEST MEMBERS LATER, run this on its own ----------
delete from auth.users where email like '%@members.test';
delete from public.club_members where membership_no between 'ARC-1001' and 'ARC-1200';
*/
