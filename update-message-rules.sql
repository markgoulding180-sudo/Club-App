-- Who can message whom (the 💬 message board). Run after update-committee-messages.sql. Safe to run again.
--   App admin and Secretary: anyone (members, committee, staff, officers)
--   Manager (any other officer, e.g. Bar Manager): staff and the other officers
--   Staff: other staff and the manager
--   Committee: the officers, and their friends
--   Members: their friends
--   Anyone can reply to someone who has messaged them.

create or replace function public.msg_kind(uid uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when p.role = 'admin' and ('owner' = any(p.perms) or p.title ilike '%app admin%') then 'owner'
    when p.role = 'admin' and p.title ilike '%secretary%' then 'secretary'
    when p.role = 'admin' then 'manager'
    when p.role = 'staff' then 'staff'
    when cardinality(p.perms) > 0 then 'committee'
    else 'member' end
  from public.profiles p where p.id = uid $$;

create or replace function public.can_message(to_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  with k as (select public.msg_kind(auth.uid()) as me, public.msg_kind(to_id) as them)
  select auth.uid() is not null and to_id is not null and to_id <> auth.uid() and (
       (select me from k) in ('owner', 'secretary')
    or ((select me from k) = 'manager'   and (select them from k) in ('staff', 'manager', 'secretary', 'owner'))
    or ((select me from k) = 'staff'     and (select them from k) in ('staff', 'manager'))
    or ((select me from k) = 'committee' and (select them from k) in ('manager', 'secretary', 'owner'))
    or public.are_friends(auth.uid(), to_id)
    or exists (select 1 from public.member_messages m where m.sender = to_id and m.recipient = auth.uid())
  );
$$;
grant execute on function public.can_message(uuid) to authenticated;

-- Phone alert for a new message: say who it's from, and open the right page
create or replace function public.push_on_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare who text; rrole text;
begin
  select case when p.role = 'admin' then coalesce(p.first_name, 'The club') || coalesce(' (' || p.title || ')', '') else coalesce(p.first_name, 'A friend') end into who
  from public.profiles p where p.id = new.sender;
  select role into rrole from public.profiles where id = new.recipient;
  insert into public.push_queue (kind, audience, user_id, title, body, url)
  values ('messages', 'user', new.recipient, '💬 ' || coalesce(who, 'A friend'), left(new.body, 140), case when rrole = 'user' then '/?go=friends' else '/?go=hub' end);
  return new;
end $$;

select p.first_name, p.title, public.msg_kind(p.id) as kind from public.profiles p
where p.role in ('admin', 'staff') or cardinality(p.perms) > 0 order by 3, 1;
