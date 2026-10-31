-- Committee (Entertainments) and the bosses can message each other on the message board.
-- Run after update-club-to-member-messages.sql. Safe to run again.

-- Who can message whom: bosses message anyone; friends message friends; anyone can reply to the club;
-- committee members (any access area, e.g. What's On) can message the bosses.
create or replace function public.can_message(to_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and to_id <> auth.uid() and (
    public.is_admin()
    or public.are_friends(auth.uid(), to_id)
    or exists (select 1 from public.member_messages m join public.profiles p on p.id = m.sender
               where m.sender = to_id and m.recipient = auth.uid() and p.role = 'admin')
    or (exists (select 1 from public.profiles me where me.id = auth.uid() and cardinality(me.perms) > 0)
        and exists (select 1 from public.profiles t where t.id = to_id and t.role = 'admin'))
  );
$$;

-- The bosses' names, for committee members and bosses to pick from
create or replace function public.club_officers()
returns table (id uuid, first_name text, last_initial text, title text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.first_name, left(coalesce(p.last_name, ''), 1), coalesce(p.title, 'Club')
  from public.profiles p
  where p.role = 'admin' and p.id <> auth.uid()
    and exists (select 1 from public.profiles me where me.id = auth.uid() and (me.role = 'admin' or cardinality(me.perms) > 0))
  order by p.title, p.first_name;
$$;
grant execute on function public.club_officers() to authenticated;

select first_name, title from public.profiles where role = 'admin' or cardinality(perms) > 0 order by role, title;
