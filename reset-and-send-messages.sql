-- Clears ALL messages (staff messages, notices, member messages, read/hidden marks), then sends a fresh set,
-- each with the right sender so the photos show. Holidays, shifts and swaps are left alone. Safe to run again.
do $$
declare heather uuid; adam uuid; luis uuid; sam uuid; stuart uuid; mark uuid; jason uuid; chloe uuid;
begin
  select id into heather from public.profiles where lower(email) = 'heather@railway.com';
  select id into adam    from public.profiles where lower(email) = 'adam@railway.com';
  select id into luis    from public.profiles where lower(email) = 'luis@railway.com';
  select id into sam     from public.profiles where role = 'admin' and (lower(email) like 'sam%@railway.com' or title ilike '%bar manager%') order by (lower(email) like 'sam%') desc limit 1;
  select id into stuart  from public.profiles where lower(email) = 'stewart@railway.com';
  if stuart is null then select id into stuart from public.profiles where role = 'admin' and title ilike '%secretary%' limit 1; end if;
  select id into mark    from public.profiles where lower(email) = 'markgoulding180@gmail.com';
  select id into jason   from public.profiles where lower(email) like 'jason%@railway.com' limit 1;
  select id into chloe   from public.profiles where lower(email) = 'chloe.martin@members.test';

  if stuart is null then raise exception 'Can''t find Stewart (stewart@railway.com). Check his email in Authentication.'; end if;
  if sam is null then raise exception 'Can''t find Sam the Bar Manager.'; end if;

  -- Clear everything
  delete from public.hidden_messages;
  delete from public.notice_reads;
  delete from public.club_notices;
  delete from public.staff_messages;
  delete from public.member_messages;

  -- 📋 Secretary (Stewart) to all staff
  insert into public.club_notices (title, body, audience, created_by, created_at)
  values ('Staff Christmas party', 'The staff Christmas do is Sun 10 Jan, 7pm in the Function Room. Partners welcome. Let Sam know numbers by 20 Dec. Stewart', 'staff', stuart, now() - interval '50 minutes');

  -- 🏛 The club (Mark) to all staff
  insert into public.club_notices (title, body, audience, created_by, created_at)
  values ('Add your photo', 'Tap the circle at the top of Home to add a photo of yourself. It shows next to your messages so everyone knows who''s who. Mark', 'staff', mark, now() - interval '40 minutes');

  -- 🍺 Manager (Sam) to Heather only, and a reply to her message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Extra shift?', 'Hi Heather, could you do Sat 28 Nov evening on the Lounge Bar? Let me know. Sam', 'staff', heather, sam, now() - interval '30 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (heather, 'other', 'Can I start at 7pm on Friday instead of 6pm?', 'done', 'Yes that''s fine, Luis will cover the first hour. Sam', now() - interval '20 minutes', sam, now() - interval '2 hours');

  -- 🍺 Manager (Sam) to Adam only, and a reply to his message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Cellar delivery', 'Hi Adam, the beer delivery is Thu morning. Could you be in at 10 to take it? Sam', 'staff', adam, sam, now() - interval '25 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (adam, 'club_problem', 'The glass washer in the Lounge Bar is leaking again.', 'done', 'Thanks Adam, engineer booked for Wednesday. Sam', now() - interval '15 minutes', sam, now() - interval '3 hours');

  -- New from Luis, waiting for the manager
  insert into public.staff_messages (staff_id, topic, body, status, created_at)
  values (luis, 'other', 'Could I have Sat 19 Dec off? It''s my brother''s wedding.', 'new', now() - interval '10 minutes');

  -- Member messages: the Secretary to Chloe about her booking, and her reply
  if chloe is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (stuart, chloe, 'Hi Chloe, your Function Room booking for Fri 6 Nov is all set. The DJ can set up from 6:30pm. Stewart, Secretary', now() - interval '45 minutes');
    insert into public.member_messages (sender, recipient, body, created_at)
    values (chloe, stuart, 'Brilliant, thank you Stewart!', now() - interval '35 minutes');
  end if;

  -- Committee: Jason (Entertainments) to Sam
  if jason is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (jason, sam, 'Hi Sam, for race night on the 21st can we have two on the bar from 7pm? Jason', now() - interval '5 minutes');
  end if;
end $$;

select 'notice' as kind, n.title as what, coalesce(p.first_name, '?') as from_who, coalesce(t.first_name, 'all ' || n.audience) as to_who
from public.club_notices n left join public.profiles p on p.id = n.created_by left join public.profiles t on t.id = n.to_user
union all select 'staff msg', left(m.body, 40), s.first_name, coalesce('reply by ' || r.first_name, 'waiting') from public.staff_messages m join public.profiles s on s.id = m.staff_id left join public.profiles r on r.id = m.replied_by
union all select 'member msg', left(m.body, 40), a.first_name, b.first_name from public.member_messages m join public.profiles a on a.id = m.sender join public.profiles b on b.id = m.recipient;
