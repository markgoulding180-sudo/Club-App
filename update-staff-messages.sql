-- Messages to staff come only from the bosses (App admin, Secretary, Bar Manager),
-- and can go to all staff or to ONE staff member. Job adverts and newsletters no longer show to staff.
-- Run after update-roles-notices-jobs.sql and add-push-notifications.sql. Safe to run again.

-- 1) A notice can be for one person
alter table public.club_notices add column if not exists to_user uuid references public.profiles on delete cascade;

-- Only that person (and the bosses) can read a one-person message
drop policy if exists "everyone signed in reads notices" on public.club_notices;
create policy "everyone signed in reads notices" on public.club_notices for select to authenticated
  using (to_user is null or to_user = auth.uid() or public.is_admin());

-- 2) Job adverts and newsletter notices are for members, not staff
update public.club_notices set audience = 'members' where audience = 'all' and (job_id is not null or title like 'Newsletter:%' or title like 'Staff wanted:%');

-- 3) Phone notification goes only to that person
create or replace function public.push_on_notice() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.to_user is not null then
    insert into public.push_queue (kind, audience, user_id, title, body, url)
    values ('news', 'user', new.to_user, '✉️ ' || new.title, left(new.body, 140), '/?go=hub');
  elsif new.title not like 'Newsletter:%' then
    insert into public.push_queue (kind, audience, title, body, url)
    values ('news', case new.audience when 'members' then 'members' when 'staff' then 'staff' else 'all' end, '📢 ' || new.title, left(new.body, 140),
            case when new.audience = 'staff' then '/?go=hub' else '/?go=notices' end);
  end if;
  return new;
end $$;

-- Check
select audience, (to_user is not null) as one_person, count(*) from public.club_notices group by 1, 2 order by 1, 2;
