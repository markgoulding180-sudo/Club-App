-- Demo messages to show "+ To-do": jobs and orders from Adam (staff) and Sam (Bar Manager).
-- Adds to what's there (doesn't clear anything). Run add-todo-list.sql first.
do $$
declare adam uuid; sam uuid; stuart uuid;
begin
  select id into adam   from public.profiles where lower(email) = 'adam@railway.com';
  select id into sam    from public.profiles where lower(email) = 'sam@railway.com';
  select id into stuart from public.profiles where lower(email) = 'stuart@railway.com';
  if adam is null or sam is null or stuart is null then raise exception 'Can''t find Adam, Sam or Stuart.'; end if;

  -- Adam → the manager (shows for Sam and Stuart under Messages from staff)
  insert into public.staff_messages (staff_id, topic, body, status, created_at) values
    (adam, 'club_problem', 'We''re down to the last box of crisps and the Coke syrup is nearly out.', 'new', now() - interval '25 minutes'),
    (adam, 'club_problem', 'The lock on the ladies'' toilet door is broken again.', 'new', now() - interval '12 minutes');

  -- Adam → Sam (chat)
  insert into public.member_messages (sender, recipient, body, subject, created_at) values
    (adam, sam, 'Sam, the cellar cooler is making a loud rattling noise. Might need an engineer.', 'Cellar cooler', now() - interval '20 minutes');

  -- Sam → Stuart (chats)
  insert into public.member_messages (sender, recipient, body, subject, created_at) values
    (sam, stuart, 'Stuart, can you put an order in for Friday: 4 kegs of Carling, 2 of Guinness and a box of lemons?', 'Order for Friday', now() - interval '15 minutes'),
    (sam, stuart, 'The fire extinguishers are due their yearly check this month. Can you book it?', 'Fire extinguisher check', now() - interval '8 minutes');
end $$;

select 'staff msg' as kind, left(body, 50) as what from public.staff_messages where created_at > now() - interval '1 hour'
union all select coalesce(subject, ''), left(body, 50) from public.member_messages where created_at > now() - interval '30 minutes';
