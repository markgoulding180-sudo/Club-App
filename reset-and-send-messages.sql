-- Clears ALL messages (staff messages, notices, member messages, read/hidden marks), then sends a fresh set,
-- each with the right sender so the photos show. If there's no Secretary yet, his messages are skipped. Holidays, shifts and swaps are left alone. Safe to run again.
do $$
declare heather uuid; adam uuid; luis uuid; sam uuid; stuart uuid; mark uuid; jason uuid; jackie uuid; joe uuid; jamie uuid; yannika uuid; chloe uuid;
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
  select id into jamie   from public.profiles where lower(email) = 'jamie@railway.com';
  select id into yannika from public.profiles where lower(email) = 'yannika@railway.com';
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
  select 'Fire drill', 'There''s a fire drill on Mon 16 Nov at 6pm. Please make sure you know where the assembly point is (front car park). Stuart', 'staff', stuart, now() - interval '58 minutes' where stuart is not null;

  -- 📋 Secretary (Stuart) to members
  insert into public.club_notices (title, body, audience, created_by, created_at)
  select 'Membership renewals', 'Membership renewals for 2027 open on Tue 1 Dec. You can pay at the bar or in the office. Stuart, Secretary', 'members', stuart, now() - interval '52 minutes' where stuart is not null;

  -- 🏛 The club (Mark) to all staff
  insert into public.club_notices (title, body, audience, created_by, created_at)
  values ('Your Messages page', 'Messages from management are under Management, and chats with other staff are under Staff. Mark', 'staff', mark, now() - interval '47 minutes');

  -- 🍺 Manager (Sam) to Heather only, and a reply to her message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Christmas Eve', 'Hi Heather, would you like to work Christmas Eve day shift 12 till 6? Double time. Sam', 'staff', heather, sam, now() - interval '33 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (heather, 'other', 'Can we get more lemons in? We ran out on Saturday night.', 'done', 'Good shout Heather, I''ve doubled the order from this week. Sam', now() - interval '22 minutes', sam, now() - interval '100 minutes');

  -- 🍺 Manager (Sam) to Adam only, and a reply to his message
  insert into public.club_notices (title, body, audience, to_user, created_by, created_at)
  values ('Stock take', 'Hi Adam, stock take is Sun 29 Nov at 10am. Can you help me with the cellar? Sam', 'staff', adam, sam, now() - interval '28 minutes');
  insert into public.staff_messages (staff_id, topic, body, status, reply, replied_at, replied_by, created_at)
  values (adam, 'club_problem', 'The light in the gents is flickering.', 'done', 'Thanks Adam, electrician is coming Thursday. Sam', now() - interval '18 minutes', sam, now() - interval '5 hours');

  -- New from Jamie, waiting for the manager
  insert into public.staff_messages (staff_id, topic, body, status, created_at)
  values (jamie, 'other', 'Could I swap to door on Fridays instead of bar? I''ve done my door badge.', 'new', now() - interval '11 minutes');

  -- 👥 Staff chats, as back-and-forth conversations (older ones already read)
  -- Adam and Sam: card machine
  insert into public.member_messages (sender, recipient, body, created_at, read_at) values
    (adam, sam,   'Sam, the card machine in the Lounge Bar keeps dropping signal.', now() - interval '70 minutes', now() - interval '65 minutes'),
    (sam,  adam,  'Thanks Adam. Try moving it nearer the till, the signal is better there. I''ll ring the bank tomorrow.', now() - interval '60 minutes', now() - interval '55 minutes'),
    (adam, sam,   'Moved it, working fine now. Cheers.', now() - interval '50 minutes', now() - interval '45 minutes'),
    (sam,  adam,  'Great, nice one. Can you keep an eye on it tonight and let me know if it drops again?', now() - interval '9 minutes', null);

  -- Joe and Adam: Carling barrel
  if joe is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (joe,  adam, 'Adam, how do you change the Carling barrel? I''m on my own Thursday.', now() - interval '80 minutes', now() - interval '75 minutes'),
      (adam, joe,  'Turn the gas off at the wall first, then twist the coupler off the old keg and onto the new one. Gas back on and pull through till it runs clear.', now() - interval '72 minutes', now() - interval '68 minutes'),
      (joe,  adam, 'Where are the spare kegs kept?', now() - interval '66 minutes', now() - interval '64 minutes'),
      (adam, joe,  'Left side of the cellar, behind the Guinness. Shout if you get stuck!', now() - interval '62 minutes', null);
  end if;

  -- Luis and Heather: lift on Friday
  if luis is not null and heather is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (luis,    heather, 'Heather, are you on Friday? I can give you a lift if you want.', now() - interval '40 minutes', now() - interval '36 minutes'),
      (heather, luis,    'Yes please! I start at 6. Could you pick me up at 5:40?', now() - interval '34 minutes', now() - interval '30 minutes'),
      (luis,    heather, 'No problem, see you at 5:40 outside yours.', now() - interval '13 minutes', null);
  end if;

  -- Yannika and Heather: jacket (Heather hasn't replied yet)
  if yannika is not null and heather is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (yannika, heather, 'Hey Heather, did you leave your black jacket in the staff room? It''s on the hook by the door.', now() - interval '20 minutes', null);
  end if;

  -- Heather to Sam: no reply yet
  if heather is not null then
    insert into public.member_messages (sender, recipient, body, created_at, read_at) values
      (heather, sam, 'Sam, can I bring my sister to the staff Christmas do?', now() - interval '16 minutes', null);
  end if;

  -- Member: the Secretary to Chloe, and her reply
  if chloe is not null and stuart is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (stuart, chloe, 'Hi Chloe, hope the party went well! Your deposit will be back in your account within 5 days. Stuart, Secretary', now() - interval '44 minutes');
    insert into public.member_messages (sender, recipient, body, created_at)
    values (chloe, stuart, 'It was brilliant, thanks so much!', now() - interval '31 minutes');
  end if;

  -- Committee: Jason (Entertainments) to Stuart
  if jason is not null and stuart is not null then
    insert into public.member_messages (sender, recipient, body, created_at)
    values (jason, stuart, 'Hi Stuart, the band for New Year''s Eve have confirmed. Can you pay their deposit? Jason', now() - interval '5 minutes');
  end if;
end $$;

select 'notice' as kind, n.title as what, coalesce(p.first_name, '?') as from_who, coalesce(t.first_name, 'all ' || n.audience) as to_who
from public.club_notices n left join public.profiles p on p.id = n.created_by left join public.profiles t on t.id = n.to_user
union all select 'staff msg', left(m.body, 40), s.first_name, coalesce('reply by ' || r.first_name, 'waiting') from public.staff_messages m join public.profiles s on s.id = m.staff_id left join public.profiles r on r.id = m.replied_by
union all select 'member msg', left(m.body, 40), a.first_name, b.first_name from public.member_messages m join public.profiles a on a.id = m.sender join public.profiles b on b.id = m.recipient;
