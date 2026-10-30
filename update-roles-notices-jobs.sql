-- =====================================================================
-- Roles (App admin, Secretary, Bar Manager, Entertainments, Staff, Member),
-- club notices to members, and Jobs (staff wanted).
-- =====================================================================

-- 1) Job title and access areas on each account
alter table public.profiles add column if not exists title text;
alter table public.profiles add column if not exists perms text[] not null default '{}';

-- Has the signed-in person got this permission? The app admin ('owner') has every permission.
create or replace function public.has_perm(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and (p = any(perms) or 'owner' = any(perms)));
$$;
grant execute on function public.has_perm(text) to authenticated;

-- Only the app admin can give or take away admin-level roles
create or replace function public.admin_set_access(pid uuid, new_role text, new_title text, new_perms text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_perm('owner') then raise exception 'Only the app admin can change roles.'; end if;
  if new_role not in ('user', 'staff', 'admin') then raise exception 'Unknown role.'; end if;
  if pid = auth.uid() and not ('owner' = any(coalesce(new_perms, '{}'))) then raise exception 'You can’t remove your own app admin access.'; end if;
  update public.profiles set role = new_role, title = nullif(trim(new_title), ''), perms = coalesce(new_perms, '{}'),
    skill = case when new_role = 'user' then null when new_role = 'staff' then coalesce(skill, 'both') else skill end
  where id = pid;
end $$;
grant execute on function public.admin_set_access(uuid, text, text, text[]) to authenticated;

-- Other admins can still make people staff or members, but not admins
create or replace function public.admin_set_profile(pid uuid, new_role text, new_skill text)
returns void language plpgsql security definer set search_path = '' as $$
declare cur text;
begin
  if not public.is_admin() then raise exception 'Only admins can change accounts.'; end if;
  select role into cur from public.profiles where id = pid;
  if (new_role = 'admin' or cur = 'admin') and new_role is distinct from cur and not public.has_perm('owner') then
    raise exception 'Only the app admin can give or remove admin roles.'; end if;
  if pid = auth.uid() and new_role <> 'admin' then raise exception 'You can’t remove your own admin access.'; end if;
  update public.profiles set
    role  = new_role,
    skill = case when new_role = 'user' then null when new_role = 'staff' then coalesce(new_skill, 'both') else new_skill end
  where id = pid;
  if new_role = 'user' or (new_role = 'admin' and new_skill is null) then
    delete from public.shifts where staff_id = pid and shift_date >= current_date;
    update public.profiles set regular_shifts = '[]'::jsonb where id = pid;
  end if;
end $$;

-- Entertainments committee can manage What's On
drop policy if exists "whats on editors manage events" on public.events;
create policy "whats on editors manage events" on public.events
  for all to authenticated using (public.has_perm('whatson')) with check (public.has_perm('whatson'));

-- 2) Notices from the club
create table if not exists public.club_notices (
  id          bigint generated always as identity primary key,
  title       text not null check (length(title) between 1 and 120),
  body        text not null check (length(body) between 1 and 1500),
  audience    text not null default 'all' check (audience in ('all', 'members', 'staff')),
  job_id      bigint,
  created_by  uuid default auth.uid() references auth.users on delete set null,
  created_at  timestamptz not null default now()
);
alter table public.club_notices enable row level security;
drop policy if exists "everyone signed in reads notices" on public.club_notices;
create policy "everyone signed in reads notices" on public.club_notices for select to authenticated using (true);
drop policy if exists "admins send notices" on public.club_notices;
create policy "admins send notices" on public.club_notices for all to authenticated using (public.is_admin()) with check (public.is_admin());

create table if not exists public.notice_reads (
  user_id   uuid not null default auth.uid() references auth.users on delete cascade,
  notice_id bigint not null references public.club_notices on delete cascade,
  read_at   timestamptz not null default now(),
  primary key (user_id, notice_id)
);
alter table public.notice_reads enable row level security;
drop policy if exists "own reads, admins count" on public.notice_reads;
create policy "own reads, admins count" on public.notice_reads for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "mark own reads" on public.notice_reads;
create policy "mark own reads" on public.notice_reads for insert to authenticated with check (user_id = auth.uid());

-- 3) Jobs: staff wanted
create table if not exists public.jobs (
  id          bigint generated always as identity primary key,
  title       text not null check (length(title) between 1 and 100),
  job_type    text,                 -- e.g. Part time, Full time, Casual
  hours       text,
  pay         text,
  description text not null default '',
  closes_on   date,
  status      text not null default 'open' check (status in ('open', 'closed')),
  created_at  timestamptz not null default now()
);
alter table public.jobs enable row level security;
drop policy if exists "everyone sees open jobs" on public.jobs;
create policy "everyone sees open jobs" on public.jobs for select to authenticated using (status = 'open' or public.is_admin());
drop policy if exists "admins manage jobs" on public.jobs;
create policy "admins manage jobs" on public.jobs for all to authenticated using (public.is_admin()) with check (public.is_admin());

create table if not exists public.job_applications (
  id          bigint generated always as identity primary key,
  job_id      bigint not null references public.jobs on delete cascade,
  user_id     uuid not null default auth.uid() references public.profiles on delete cascade,
  note        text check (note is null or length(note) <= 600),
  phone       text,
  created_at  timestamptz not null default now(),
  unique (job_id, user_id)
);
alter table public.job_applications enable row level security;
drop policy if exists "own applications, admins all" on public.job_applications;
create policy "own applications, admins all" on public.job_applications for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "members apply" on public.job_applications;
create policy "members apply" on public.job_applications for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "members withdraw" on public.job_applications;
create policy "members withdraw" on public.job_applications for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- Names and contact details of applicants, for admins
create or replace function public.job_applicants(jid bigint)
returns table (id bigint, user_id uuid, first_name text, last_name text, email text, phone text, membership_no text, note text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id, a.user_id, p.first_name, p.last_name, p.email, coalesce(a.phone, p.phone), p.membership_no, a.note, a.created_at
  from public.job_applications a join public.profiles p on p.id = a.user_id
  where a.job_id = jid and public.is_admin() order by a.created_at;
$$;
grant execute on function public.job_applicants(bigint) to authenticated;

-- 4) Make Mark the app admin (sees everything, can switch views, gives out roles)
update public.profiles set role = 'admin', title = 'App admin', perms = array['owner']
where lower(email) = 'markgoulding180@gmail.com';
select first_name, email, role, title, perms from public.profiles where lower(email) = 'markgoulding180@gmail.com';
