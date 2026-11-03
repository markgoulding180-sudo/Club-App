-- Clears ALL messages (staff messages, notices, member messages, read/hidden marks), then sends a fresh set,
-- each with the right sender so the photos show. If there's no Secretary yet, his messages are skipped. Holidays, shifts and swaps are left alone. Safe to run again.
do $$
declare heather uuid; adam uuid; luis uuid; sam uuid; stuart uuid; mark uuid; jason uuid; jackie uuid; joe uuid; chloe uuid;
begin
  select id into heather from public.profiles where lower(email) = 'heather@railway.com';
  select id into adam    from public.profiles where lower(email) = 'adam@railway.com';
  select id into luis    from public.profiles where lower(email) = 'luis@railway.com';
  select id into sam     from public.profiles where role = 'admin' and (lower(email) like 'sam%@railway.com' or title ilike '%bar manager%') order by (lower(email) like 'sam%') desc limit 1;
  select id into stuart  from public.profiles where lower(email) = 'stuart@railway.com';
  if stuart is null then select id into stuart from public.profiles where role = 'admin' and title ilike '%secretary%' limit 1; end if;
  select id into mark    from public.profiles where lower(email) = 'markgoulding180@gmail.com';
  select id into jason   from public.profiles where lower(email) like 'jason%@railway.com' limit 1;
  select id into jackie  from public.profiles where lower(email) like 'jackie%@railway.com' limit 1;
  select id into joe     from public.profiles where lower(email) = 'joe@railway.com';
  select id into chloe   from public.profiles where lower(email) = 'chloe.martin@members.test';

  if sam is null then raise exception 'Can''t find Sam the Bar Manager.'; end if;

  -- Clear everything
  delete from public.hidden_messages;
  delete from public.notice_reads;
  delete from public.club_notices;
  delete from public.staff_messages;
  delete from public.member_messages;

  -- 📋 Secretary (Stuart) to all staff
  insert into public.club_notices (title, body, audience, created_by, created_at)
  select 'New uniform polo shirts', 'New black polo shirts with the club badge are in the office. Please collect two each before Fri 13 Nov and wear them from then on. Stuart', 'staff', stuart, now() - interval '55 minutes' where stuart is not null;

  -- 📋 Secretary (Stuart) to members
  insert into public.club_notices (title, body, audience, created_by, created_at)
  select 'AGM date set', 'The club AGM is Sun 6 Dec at 2pm in the Function Room. All full members are welcome to come and vote. Stuart, Secretary', 'members', stuart, now() - interval '50 minutes' where stuart is not null;

  -- 🏛 The club (Mark) to all staff
  insert into public.club_notices (title, body, audience, created_by, created_at)
  values ('Try the new staff chat', 'You can now message each other: tap 💬 Message staff on Home. Use Message the manager for anything that needs to go on record. Mark', 'staff', mark, now() - interval '45 minutes');

  -- 🍺 Manager (Sam) to Heather only, and a reply to her message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Training on the new till', 'Hi Heather, the till company are in Wed 11 Nov at 4pm to show us the new card machine. Can you come in for an hour? Paid, of course. Sam', 'staff', heather, sam, now() - interval '35 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (heather, 'club_problem', 'The ice machine in the Lounge Bar isn''t making ice.', 'done', 'Thanks Heather, I''ve reset it and it''s working again. Use the cellar one if it stops. Sam', now() - interval '25 minutes', sam, now() - interval '90 minutes');

  -- 🍺 Manager (Sam) to Adam only, and a reply to his message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Key holder', 'Hi Adam, from next week you''ll be a key holder for Sunday lock-up. I''ll go through the alarm with you on Saturday. Sam', 'staff', adam, sam, now() - interval '30 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (adam, 'complaint', 'A guest was rude to Yannika on the door on Saturday when she asked for his card.', 'done', 'Thanks for telling me Adam. I''ve spoken to the member who signed him in, he won''t be back. Sam', now() - interval '20 minutes', sam, now() - interval '4 hours');

  -- New from Joe, waiting for the manager
  insert into public.staff_messages (staff_id, topic, body, status, created_at)
  values (joe, 'ill', 'Feeling rough with a cold, should be fine for my shift Thursday but letting you know.', 'new', now() - interval '12 minutes');

  -- 👥 Staff chat: Luis and Heather
  if luis is not null and heather is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at)
    values (luis, heather, 'Hi Heather, could you cover the first hour of my shift on Sat 14th? I''ll do your Sunday close in return.', now() - interval '40 minutes', null);
  end if;
  -- 👥 Staff chat: Adam to Sam (manager)
  insert into public.member_messages (sender, recipient, body, created_at)
  values (adam, sam, 'Sam, the Guinness is running low, only one keg left in the cellar.', now() - interval '8 minutes');

  -- Member messages: the Secretary to Chloe, and her reply
  if chloe is not null and stuart is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (stuart, chloe, 'Hi Chloe, just a reminder the Function Room needs to be clear by midnight on Fri 6 Nov. Have a great party! Stuart, Secretary', now() - interval '42 minutes');
    insert into public.member_messages (sender, recipient, body, created_at)
    values (chloe, stuart, 'Will do, thanks for the reminder Stuart.', now() - interval '33 minutes');
  end if;

  -- Committee: Jackie (Entertainments) to Stuart
  if jackie is not null and stuart is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (jackie, stuart, 'Hi Stuart, can we put the Christmas raffle on the AGM agenda? Jackie', now() - interval '6 minutes');
  end if;
end $$;

select 'notice' as kind, n.title as what, coalesce(p.first_name, '?') as from_who, coalesce(t.first_name, 'all ' || n.audience) as to_who
from public.club_notices n left join public.profiles p on p.id = n.created_by left join public.profiles t on t.id = n.to_user
union all select 'staff msg', left(m.body, 40), s.first_name, coalesce('reply by ' || r.first_name, 'waiting') from public.staff_messages m join public.profiles s on s.id = m.staff_id left join public.profiles r on r.id = m.replied_by
union all select 'member msg', left(m.body, 40), a.first_name, b.first_name from public.member_messages m join public.profiles a on a.id = m.sender join public.profiles b on b.id = m.recipient;
