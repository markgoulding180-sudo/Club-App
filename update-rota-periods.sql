-- =====================================================================
-- 4-weekly rotas: draft → publish, can't-work rules, withdraw, swaps,
-- and staff who leave come off their future shifts.
-- =====================================================================

-- ---------- Rota periods ----------
-- Rotas run 4 weeks from a Monday. The first one starts Mon 2 Nov 2026; every 28 days after that is the next.
create or replace function public.rota_anchor() returns date language sql immutable as $$ select date '2026-11-02' $$;
create or replace function public.rota_period_start(d date) returns date language sql immutable as $$
  select public.rota_anchor() + (floor((d - public.rota_anchor())::numeric / 28) * 28)::int
$$;

create table if not exists public.rota_periods (
  start_date   date primary key,
  published_at timestamptz,
  published_by uuid references auth.users on delete set null
);
alter table public.rota_periods enable row level security;
drop policy if exists "staff and admins see rota periods" on public.rota_periods;
create policy "staff and admins see rota periods" on public.rota_periods
  for select to authenticated using (public.is_staff_or_admin());

-- Is the rota for this day published? (Days before the first 4-week rota count as published.)
create or replace function public.rota_published(d date) returns boolean
language sql stable security definer set search_path = '' as $$
  select d < public.rota_anchor() or exists (
    select 1 from public.rota_periods p where p.start_date = public.rota_period_start(d) and p.published_at is not null)
$$;
grant execute on function public.rota_published(date) to authenticated;

-- Admin: publish (or take back) a rota
create or replace function public.admin_publish_rota(period_start date, publish boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can publish the rota.'; end if;
  if period_start <> public.rota_period_start(period_start) then raise exception 'That isn''t the start of a rota.'; end if;
  insert into public.rota_periods (start_date, published_at, published_by)
  values (period_start, case when publish then now() end, case when publish then auth.uid() end)
  on conflict (start_date) do update set published_at = excluded.published_at, published_by = excluded.published_by;
end $$;
grant execute on function public.admin_publish_rota(date, boolean) to authenticated;

-- Staff only see shifts once that rota is published. Admins see everything.
drop policy if exists "staff and admins see the rota" on public.shifts;
create policy "staff and admins see the rota" on public.shifts
  for select to authenticated using (public.is_admin() or (public.is_staff_or_admin() and public.rota_published(shift_date)));

-- ---------- Can't work: reason, 2 days' notice, 2 per rota, can withdraw ----------
create or replace function public.staff_update_shift(shift_id bigint, new_status text, why text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare sh public.shifts; used int;
begin
  if new_status <> 'cannot_work' then raise exception 'Staff can only say they can''t make a shift.'; end if;
  if length(trim(coalesce(why, ''))) < 3 then raise exception 'Please give a reason.'; end if;
  select * into sh from public.shifts where id = shift_id and staff_id = auth.uid() for update;
  if sh.id is null or sh.status not in ('assigned', 'confirmed') or not public.rota_published(sh.shift_date) then raise exception 'Shift not found or already changed.'; end if;
  if sh.shift_date < current_date + 2 then raise exception 'That shift is less than 2 days away. Please phone the manager.'; end if;
  select count(*) into used from public.shifts
   where staff_id = auth.uid() and id <> sh.id and public.rota_period_start(shift_date) = public.rota_period_start(sh.shift_date)
     and (status = 'cannot_work' or decision is not null);
  if used >= 2 then raise exception 'You''ve already asked off 2 shifts on this rota. Please speak to the manager.'; end if;
  update public.shifts set status = 'cannot_work', reason = trim(why), decision = null, decided_at = null where id = sh.id;
  update public.shift_swaps set status = 'cancelled', decided_at = now()
   where status in ('asked', 'accepted') and (from_shift = sh.id or to_shift = sh.id);
end $$;
grant execute on function public.staff_update_shift(bigint, text, text) to authenticated;

create or replace function public.staff_withdraw_cantwork(shift_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shifts set status = 'assigned', reason = null
  where id = shift_id and staff_id = auth.uid() and status = 'cannot_work' and not covered and decision is null;
  if not found then raise exception 'The manager has already dealt with this one.'; end if;
end $$;
grant execute on function public.staff_withdraw_cantwork(bigint) to authenticated;

-- ---------- Staff who leave come off their future shifts ----------
create or replace function public.admin_set_profile(pid uuid, new_role text, new_skill text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can change accounts.'; end if;
  if pid = auth.uid() and new_role <> 'admin' then raise exception 'You can’t remove your own admin access.'; end if;
  update public.profiles set
    role  = new_role,
    skill = case when new_role = 'user' then null
                 when new_role = 'staff' then coalesce(new_skill, 'both')
                 else new_skill end
  where id = pid;
  if new_role = 'user' or (new_role = 'admin' and new_skill is null) then
    delete from public.shifts where staff_id = pid and shift_date >= current_date;   -- their shifts show as needing someone
    update public.profiles set regular_shifts = '[]'::jsonb where id = pid;
  end if;
end $$;

-- ---------- Shift swaps ----------
create table if not exists public.shift_swaps (
  id          bigint generated always as identity primary key,
  from_shift  bigint not null references public.shifts on delete cascade,
  to_shift    bigint not null references public.shifts on delete cascade,
  from_staff  uuid not null references public.profiles on delete cascade,
  to_staff    uuid not null references public.profiles on delete cascade,
  note        text,
  status      text not null default 'asked' check (status in ('asked', 'accepted', 'declined', 'approved', 'refused', 'cancelled')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
create index if not exists shift_swaps_from_idx on public.shift_swaps (from_staff);
create index if not exists shift_swaps_to_idx on public.shift_swaps (to_staff);
alter table public.shift_swaps enable row level security;
drop policy if exists "people in the swap and admins see it" on public.shift_swaps;
create policy "people in the swap and admins see it" on public.shift_swaps
  for select to authenticated using (from_staff = auth.uid() or to_staff = auth.uid() or public.is_admin());
-- (all changes go through the functions below)

create or replace function public.can_do_job(skill text, job text) returns boolean language sql immutable as $$
  select skill = 'both' or (job = 'door' and skill = 'door') or (job <> 'door' and skill = 'bar')
$$;

-- One shift a day, except while the manager approves a swap
create or replace function public.shifts_one_a_day()
returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('app.swapping', true), '') = '1' then return new; end if;
  if new.status in ('assigned', 'confirmed', 'late') and exists (
    select 1 from public.shifts o
    where o.staff_id = new.staff_id and o.shift_date = new.shift_date and o.id <> new.id
      and o.status in ('assigned', 'confirmed', 'late')) then
    raise exception 'They are already working that day.';
  end if;
  return new;
end $$;
drop trigger if exists shifts_one_a_day on public.shifts;
create trigger shifts_one_a_day before insert or update of staff_id, shift_date, status on public.shifts
  for each row execute function public.shifts_one_a_day();

-- Staff: ask a colleague to swap
create or replace function public.staff_ask_swap(mine bigint, theirs bigint, why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare a public.shifts; b public.shifts; sa text; sb text; new_id bigint;
begin
  select * into a from public.shifts where id = mine;
  select * into b from public.shifts where id = theirs;
  if a.id is null or a.staff_id <> auth.uid() or a.status not in ('assigned', 'confirmed') then raise exception 'That isn''t one of your shifts.'; end if;
  if b.id is null or b.staff_id = auth.uid() or b.status not in ('assigned', 'confirmed') then raise exception 'That shift can''t be swapped.'; end if;
  if a.shift_date <= current_date or b.shift_date <= current_date then raise exception 'Swaps need to be for tomorrow or later.'; end if;
  if not public.rota_published(a.shift_date) or not public.rota_published(b.shift_date) then raise exception 'That rota isn''t published yet.'; end if;
  if a.shift_date = b.shift_date then raise exception 'Pick a shift on a different day.'; end if;
  if exists (select 1 from public.shifts where staff_id = a.staff_id and shift_date = b.shift_date and status in ('assigned', 'confirmed', 'late')) then
    raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.shifts where staff_id = b.staff_id and shift_date = a.shift_date and status in ('assigned', 'confirmed', 'late')) then
    raise exception 'They''re already working on your day.'; end if;
  select skill into sa from public.profiles where id = a.staff_id;
  select skill into sb from public.profiles where id = b.staff_id;
  if not public.can_do_job(sa, b.job) or not public.can_do_job(sb, a.job) then raise exception 'You can''t both do each other''s jobs.'; end if;
  if exists (select 1 from public.shift_swaps where status in ('asked', 'accepted') and (from_shift in (a.id, b.id) or to_shift in (a.id, b.id))) then
    raise exception 'One of those shifts already has a swap waiting.'; end if;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note)
  values (a.id, b.id, a.staff_id, b.staff_id, nullif(trim(why), '')) returning id into new_id;
  return new_id;
end $$;
grant execute on function public.staff_ask_swap(bigint, bigint, text) to authenticated;

-- Staff: answer a swap someone asked you for
create or replace function public.staff_answer_swap(swap_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shift_swaps set status = case when yes then 'accepted' else 'declined' end, decided_at = case when yes then null else now() end
  where id = swap_id and to_staff = auth.uid() and status = 'asked';
  if not found then raise exception 'That swap has already been dealt with.'; end if;
end $$;
grant execute on function public.staff_answer_swap(bigint, boolean) to authenticated;

-- Staff: cancel a swap you asked for (before the manager approves)
create or replace function public.staff_cancel_swap(swap_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shift_swaps set status = 'cancelled', decided_at = now()
  where id = swap_id and from_staff = auth.uid() and status in ('asked', 'accepted');
  if not found then raise exception 'That swap has already been dealt with.'; end if;
end $$;
grant execute on function public.staff_cancel_swap(bigint) to authenticated;

-- Admin: approve (swap the two shifts over) or refuse
create or replace function public.admin_decide_swap(swap_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare sw public.shift_swaps; a public.shifts; b public.shifts;
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into sw from public.shift_swaps where id = swap_id for update;
  if sw.id is null or sw.status <> 'accepted' then raise exception 'That swap isn''t waiting for you.'; end if;
  if not yes then update public.shift_swaps set status = 'refused', decided_at = now() where id = sw.id; return; end if;
  select * into a from public.shifts where id = sw.from_shift for update;
  select * into b from public.shifts where id = sw.to_shift for update;
  if a.staff_id <> sw.from_staff or b.staff_id <> sw.to_staff or a.status not in ('assigned', 'confirmed') or b.status not in ('assigned', 'confirmed') then
    update public.shift_swaps set status = 'cancelled', decided_at = now() where id = sw.id;
    raise exception 'The rota has changed since they asked, so this swap was cancelled.';
  end if;
  perform set_config('app.swapping', '1', true);
  update public.shifts set staff_id = case when id = a.id then b.staff_id else a.staff_id end where id in (a.id, b.id);
  perform set_config('app.swapping', '', true);
  update public.shift_swaps set status = 'approved', decided_at = now() where id = sw.id;
end $$;
grant execute on function public.admin_decide_swap(bigint, boolean) to authenticated;
