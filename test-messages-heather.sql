-- TEST: messages for Heather from each sender, so the Messages page shows every section.
-- Run after update-message-senders.sql. Safe to run again.
do $$
declare heather uuid; sam uuid; stuart uuid; mark uuid; m bigint;
begin
  select id into heather from public.profiles where lower(email) = 'heather@railway.com';
  select id into sam     from public.profiles where lower(email) = 'sam@railway.com';
  select id into stuart  from public.profiles where lower(email) = 'stuart@railway.com';
  select id into mark    from public.profiles where lower(email) = 'markgoulding180@gmail.com';
  delete from public.club_notices where title like '%(test)';
  delete from public.staff_messages where staff_id = heather and body like '%(test)';

  -- 🍺 From the manager (Sam): a private message, and a reply to Heather's own message
  insert into public.club_notices (title, body, audience, to_user, created_by)
  values ('Extra shift? (test)', 'Hi Heather, could you do Sat 28 Nov evening on the Lounge Bar? Let me know. Sam', 'staff', heather, sam);
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by)
  values (heather, 'other', 'Can I start at 7pm on Friday instead of 6pm? (test)', 'done', 'Yes that''s fine, Luis will cover the first hour.', now(), sam);

  -- 📋 From the secretary (Stuart): a notice to all staff
  insert into public.club_notices (title, body, audience, created_by)
  values ('Christmas party for staff (test)', 'The staff Christmas do is Sun 10 Jan, 7pm in the Function Room. Partners welcome. Stuart, Secretary', 'staff', stuart);

  -- 🏛 From the club (you, App admin): a private message
  insert into public.club_notices (title, body, audience, to_user, created_by)
  values ('Welcome to the new app (test)', 'Hi Heather, thanks for trying out the new staff app. Any problems, tell Sam or me. Mark', 'staff', heather, mark);
end $$;

select n.title, coalesce(p.title, '?') as from_who, case when n.to_user is null then 'all staff' else 'Heather only' end as to_whom
from public.club_notices n left join public.profiles p on p.id = n.created_by where n.title like '%(test)' order by n.id;
