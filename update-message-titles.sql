-- Every chat message has a title (what it's about). Replies keep the same title,
-- so each topic is its own conversation. Run after update-message-rules.sql. Safe to run again.
alter table public.member_messages add column if not exists subject text;
alter table public.member_messages drop constraint if exists member_messages_subject_len;
alter table public.member_messages add constraint member_messages_subject_len check (subject is null or length(subject) <= 80);

-- Phone alert shows who and the title
create or replace function public.push_on_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare who text; rrole text;
begin
  select case when p.role = 'admin' then coalesce(p.first_name, 'The club') || coalesce(' (' || p.title || ')', '') else coalesce(p.first_name, 'A friend') end into who
  from public.profiles p where p.id = new.sender;
  select role into rrole from public.profiles where id = new.recipient;
  insert into public.push_queue (kind, audience, user_id, title, body, url)
  values ('messages', 'user', new.recipient, '💬 ' || coalesce(who, 'A friend') || coalesce(': ' || nullif(new.subject, ''), ''), left(new.body, 140),
          case when rrole = 'user' then '/?go=friends' else '/?go=hub' end);
  return new;
end $$;
select 'Message titles ready' as done;
