-- Staff can see who each message came from (Bar Manager, Secretary…): staff may read the club officers' names and titles.
create or replace function public.club_officers()
returns table (id uuid, first_name text, last_initial text, title text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.first_name, left(coalesce(p.last_name, ''), 1), coalesce(p.title, 'Club')
  from public.profiles p
  where p.role = 'admin' and p.id <> auth.uid()
    and exists (select 1 from public.profiles me where me.id = auth.uid() and (me.role in ('admin', 'staff') or cardinality(me.perms) > 0))
  order by p.title, p.first_name;
$$;
grant execute on function public.club_officers() to authenticated;
-- Remember who answered a staff message
alter table public.staff_messages add column if not exists replied_by uuid references auth.users on delete set null;
create or replace function public.set_replied_by() returns trigger language plpgsql security definer set search_path = '' as $$
begin if new.reply is distinct from old.reply and new.reply is not null then new.replied_by := auth.uid(); end if; return new; end $$;
drop trigger if exists set_replied_by on public.staff_messages;
create trigger set_replied_by before update of reply on public.staff_messages for each row execute function public.set_replied_by();
select 'done' as result;
