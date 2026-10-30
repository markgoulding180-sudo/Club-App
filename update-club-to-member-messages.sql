-- The club (secretary, manager, app admin) can message any member on their message board, and the member can reply.
-- Run after update-member-messages.sql and update-roles-notices-jobs.sql.
create or replace function public.can_message(to_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and to_id <> auth.uid() and (
    public.is_admin()                                                                 -- club officers can message anyone
    or public.are_friends(auth.uid(), to_id)                                          -- members message their friends
    or exists (select 1 from public.member_messages m join public.profiles p on p.id = m.sender
               where m.sender = to_id and m.recipient = auth.uid() and p.role = 'admin') -- reply to the club
  );
$$;
grant execute on function public.can_message(uuid) to authenticated;

drop policy if exists "members message their friends" on public.member_messages;
create policy "members message their friends" on public.member_messages
  for insert to authenticated with check (sender = auth.uid() and read_at is null and public.can_message(recipient));

-- Names of everyone I have a conversation with (members can't otherwise read other people's profiles)
create or replace function public.msg_contacts()
returns table (id uuid, first_name text, last_initial text, title text, is_club boolean)
language sql stable security definer set search_path = '' as $$
  select distinct p.id, p.first_name, left(coalesce(p.last_name, ''), 1), p.title, p.role = 'admin'
  from public.member_messages m
  join public.profiles p on p.id = case when m.sender = auth.uid() then m.recipient else m.sender end
  where auth.uid() in (m.sender, m.recipient);
$$;
grant execute on function public.msg_contacts() to authenticated;
