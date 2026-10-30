-- =====================================================================
-- Club membership register, Going / Interested on What's On, and Friends.
-- Friends are added by membership number and must accept the request.
-- =====================================================================

-- 1) Membership register: every club member (whether or not they use the app)
create table if not exists public.club_members (
  membership_no  text primary key check (membership_no ~ '^[A-Za-z0-9-]{2,20}$'),
  first_name     text not null,
  last_name      text not null,
  tier           text,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);
alter table public.club_members enable row level security;
drop policy if exists "admins manage the register" on public.club_members;
create policy "admins manage the register" on public.club_members for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 2) Going / Interested. event_key: 'b<booking id>' for club events, 'e<event id>' for What's On items
create table if not exists public.event_rsvps (
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  event_key  text not null check (event_key ~ '^[be][0-9]+$'),
  event_date date not null,
  status     text not null check (status in ('going', 'interested')),
  created_at timestamptz not null default now(),
  primary key (user_id, event_key)
);
create index if not exists event_rsvps_key_idx on public.event_rsvps (event_key);
alter table public.event_rsvps enable row level security;
drop policy if exists "own rsvps, admins all" on public.event_rsvps;
create policy "own rsvps, admins all" on public.event_rsvps for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "members set their own rsvps" on public.event_rsvps;
create policy "members set their own rsvps" on public.event_rsvps for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Counts for each event (no names)
create or replace function public.get_rsvp_counts(keys text[])
returns table (event_key text, going int, interested int)
language sql stable security definer set search_path = '' as $$
  select r.event_key, count(*) filter (where r.status = 'going')::int, count(*) filter (where r.status = 'interested')::int
  from public.event_rsvps r where r.event_key = any(keys) group by r.event_key;
$$;
grant execute on function public.get_rsvp_counts(text[]) to authenticated;

-- 3) Friends
create table if not exists public.friendships (
  id          bigint generated always as identity primary key,
  requester   uuid not null default auth.uid() references public.profiles on delete cascade,
  addressee   uuid not null references public.profiles on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  likes       text[] not null default '{}',          -- event types they share, e.g. {bingo,quiz}
  created_at  timestamptz not null default now(),
  check (requester <> addressee)
);
create unique index if not exists friendships_pair on public.friendships (least(requester, addressee), greatest(requester, addressee));
alter table public.friendships enable row level security;
drop policy if exists "people in the friendship see it" on public.friendships;
create policy "people in the friendship see it" on public.friendships for select to authenticated using (requester = auth.uid() or addressee = auth.uid());
-- (changes go through the functions below)

-- Look up a membership number: first name and surname initial only.
-- An app account only counts as that member if its surname matches the register (stops people claiming someone else's number).
create or replace function public.find_member(no text)
returns table (first_name text, last_initial text, on_app boolean)
language sql stable security definer set search_path = '' as $$
  with reg as (select c.first_name, c.last_name from public.club_members c where upper(c.membership_no) = upper(trim(no)) and c.active),
       app as (select p.id, p.first_name, p.last_name from public.profiles p where upper(p.membership_no) = upper(trim(no)) and p.id <> auth.uid() and not exists (select 1 from public.club_members c where upper(c.membership_no) = upper(p.membership_no) and lower(c.last_name) <> lower(coalesce(p.last_name, ''))) limit 1)
  select coalesce((select first_name from reg), (select first_name from app)),
         left(coalesce((select last_name from reg), (select last_name from app), ''), 1),
         exists (select 1 from app)
  where auth.uid() is not null and (exists (select 1 from reg) or exists (select 1 from app));
$$;
grant execute on function public.find_member(text) to authenticated;

create or replace function public.send_friend_request(no text, shared text[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
declare them uuid;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  select p.id into them from public.profiles p where upper(p.membership_no) = upper(trim(no)) and p.id <> auth.uid() and not exists (select 1 from public.club_members c where upper(c.membership_no) = upper(p.membership_no) and lower(c.last_name) <> lower(coalesce(p.last_name, ''))) limit 1;
  if them is null then raise exception 'That member isn''t on the app yet. Ask them to register with their membership number.'; end if;
  insert into public.friendships (requester, addressee, likes) values (auth.uid(), them, coalesce(shared, '{}'))
  on conflict (least(requester, addressee), greatest(requester, addressee))
  do update set likes = excluded.likes, status = case when public.friendships.status = 'declined' then 'pending' else public.friendships.status end,
                requester = case when public.friendships.status = 'declined' then excluded.requester else public.friendships.requester end,
                addressee = case when public.friendships.status = 'declined' then excluded.addressee else public.friendships.addressee end;
end $$;
grant execute on function public.send_friend_request(text, text[]) to authenticated;

create or replace function public.answer_friend(fid bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.friendships set status = case when yes then 'accepted' else 'declined' end where id = fid and addressee = auth.uid() and status = 'pending';
  if not found then raise exception 'That request has already been answered.'; end if;
end $$;
grant execute on function public.answer_friend(bigint, boolean) to authenticated;

create or replace function public.update_friend_likes(fid bigint, shared text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.friendships set likes = coalesce(shared, '{}') where id = fid and auth.uid() in (requester, addressee);
end $$;
grant execute on function public.update_friend_likes(bigint, text[]) to authenticated;

create or replace function public.remove_friend(fid bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.friendships where id = fid and auth.uid() in (requester, addressee);
end $$;
grant execute on function public.remove_friend(bigint) to authenticated;

-- My friends and requests, with names
create or replace function public.my_friends()
returns table (id bigint, other uuid, first_name text, last_initial text, status text, incoming boolean, likes text[])
language sql stable security definer set search_path = '' as $$
  select f.id, o.id, o.first_name, left(coalesce(o.last_name, ''), 1), f.status, f.addressee = auth.uid(), f.likes
  from public.friendships f
  join public.profiles o on o.id = case when f.requester = auth.uid() then f.addressee else f.requester end
  where auth.uid() in (f.requester, f.addressee) and f.status <> 'declined';
$$;
grant execute on function public.my_friends() to authenticated;

-- What my friends are going to / interested in
drop function if exists public.friends_rsvps(date);
create or replace function public.friends_rsvps(from_date date)
returns table (event_key text, who uuid, first_name text, status text)
language sql stable security definer set search_path = '' as $$
  select r.event_key, r.user_id, p.first_name, r.status
  from public.friendships f
  join public.event_rsvps r on r.user_id = case when f.requester = auth.uid() then f.addressee else f.requester end
  join public.profiles p on p.id = r.user_id
  where f.status = 'accepted' and auth.uid() in (f.requester, f.addressee) and r.event_date >= from_date;
$$;
grant execute on function public.friends_rsvps(date) to authenticated;
