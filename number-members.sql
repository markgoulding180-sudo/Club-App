-- Membership numbers 1, 2, 3 … for every member on the app (oldest account first),
-- kept in step with the membership register and ticket reservations. Members can then find each other
-- under Friends by typing the number, e.g. 9. Staff and officers aren't numbered. Safe to run once;
-- running it again renumbers in the same order.

-- Allow short numbers like 9 (it used to need at least 2 characters)
alter table public.club_members drop constraint if exists club_members_membership_no_check;
alter table public.club_members add constraint club_members_membership_no_check check (membership_no ~ '^[A-Za-z0-9-]{1,20}$');

do $$
declare r record; n int := 0; old text; t text;
begin
  -- Park everyone's current number first, so new numbers never clash with old ones
  create temp table renum on commit drop as
    select p.id, p.membership_no as old_no, p.first_name, p.last_name, row_number() over (order by u.created_at, p.last_name, p.first_name) as new_no
    from public.profiles p left join auth.users u on u.id = p.id
    where p.role = 'user' and p.first_name is not null;

  for r in select * from renum order by new_no loop
    -- Tier from their old register row, if they had one
    select c.tier into t from public.club_members c where upper(c.membership_no) = upper(coalesce(r.old_no, '')) limit 1;
    delete from public.club_members c where upper(c.membership_no) = upper(coalesce(r.old_no, '')) and lower(c.last_name) = lower(coalesce(r.last_name, ''));
    insert into public.club_members (membership_no, first_name, last_name, tier, active)
    values (r.new_no::text, r.first_name, coalesce(nullif(r.last_name, ''), '-'), coalesce(t, 'Full'), true)
    on conflict (membership_no) do update set first_name = excluded.first_name, last_name = excluded.last_name, tier = excluded.tier, active = true;
    update public.profiles set membership_no = r.new_no::text where id = r.id;
    update public.ticket_reservations set membership_no = r.new_no::text where user_id = r.id;
    t := null;
  end loop;
end $$;

select p.membership_no as "Number", p.first_name || ' ' || coalesce(p.last_name, '') as "Member", p.email
from public.profiles p where p.role = 'user' order by p.membership_no::int;
