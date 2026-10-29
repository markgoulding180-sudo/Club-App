-- =====================================================================
-- Swap requests to everyone, and holiday only before the rota is out.
-- Run after update-rota-periods.sql.
-- =====================================================================

-- A staff member asks everyone to swap one of their shifts
create table if not exists public.swap_requests (
  id          bigint generated always as identity primary key,
  shift_id    bigint not null references public.shifts on delete cascade,
  staff_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  note        text,
  status      text not null default 'open' check (status in ('open', 'matched', 'cancelled')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
create unique index if not exists swap_requests_one_open on public.swap_requests (shift_id) where status = 'open';
alter table public.swap_requests enable row level security;
drop policy if exists "staff see swap requests" on public.swap_requests;
create policy "staff see swap requests" on public.swap_requests
  for select to authenticated using (public.is_staff_or_admin());

-- Colleagues offer one of their shifts back, or say no thanks (shift_id empty)
create table if not exists public.swap_offers (
  id          bigint generated always as identity primary key,
  request_id  bigint not null references public.swap_requests on delete cascade,
  shift_id    bigint references public.shifts on delete cascade,
  staff_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  status      text not null default 'offered' check (status in ('offered', 'passed', 'accepted', 'declined', 'withdrawn')),
  created_at  timestamptz not null default now()
);
create unique index if not exists swap_offers_one_each on public.swap_offers (request_id, staff_id) where status in ('offered', 'passed', 'accepted');
alter table public.swap_offers enable row level security;
drop policy if exists "people involved see swap offers" on public.swap_offers;
create policy "people involved see swap offers" on public.swap_offers
  for select to authenticated using (
    staff_id = auth.uid() or public.is_admin()
    or exists (select 1 from public.swap_requests r where r.id = request_id and r.staff_id = auth.uid()));

-- Ask everyone
create or replace function public.staff_ask_swap_all(my_shift bigint, why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare a public.shifts; new_id bigint;
begin
  select * into a from public.shifts where id = my_shift;
  if a.id is null or a.staff_id <> auth.uid() or a.status not in ('assigned', 'confirmed') then raise exception 'That isn''t one of your shifts.'; end if;
  if a.shift_date <= current_date then raise exception 'Swaps need to be for tomorrow or later.'; end if;
  if not public.rota_published(a.shift_date) then raise exception 'That rota isn''t published yet.'; end if;
  if exists (select 1 from public.shift_swaps where status in ('asked', 'accepted') and a.id in (from_shift, to_shift)) then
    raise exception 'This shift already has a swap waiting.'; end if;
  insert into public.swap_requests (shift_id, staff_id, note) values (a.id, auth.uid(), nullif(trim(why), '')) returning id into new_id;
  return new_id;
exception when unique_violation then raise exception 'You''ve already asked everyone to swap this shift.';
end $$;
grant execute on function public.staff_ask_swap_all(bigint, text) to authenticated;

create or replace function public.staff_cancel_swap_request(req bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.swap_requests set status = 'cancelled', decided_at = now() where id = req and staff_id = auth.uid() and status = 'open';
  if not found then raise exception 'That request has already closed.'; end if;
  update public.swap_offers set status = 'declined' where request_id = req and status = 'offered';
end $$;
grant execute on function public.staff_cancel_swap_request(bigint) to authenticated;

-- Offer one of my shifts in exchange
create or replace function public.staff_offer_swap(req bigint, my_shift bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare r public.swap_requests; a public.shifts; b public.shifts; sa text; sb text; new_id bigint;
begin
  select * into r from public.swap_requests where id = req;
  if r.id is null or r.status <> 'open' then raise exception 'That request has closed.'; end if;
  select * into a from public.shifts where id = r.shift_id;          -- their shift
  select * into b from public.shifts where id = my_shift;            -- my shift
  if b.id is null or b.staff_id <> auth.uid() or b.status not in ('assigned', 'confirmed') then raise exception 'That isn''t one of your shifts.'; end if;
  if r.staff_id = auth.uid() then raise exception 'That''s your own request.'; end if;
  if b.shift_date <= current_date or not public.rota_published(b.shift_date) then raise exception 'Pick a shift from tomorrow on the published rota.'; end if;
  if a.shift_date = b.shift_date then raise exception 'Pick a shift on a different day.'; end if;
  if exists (select 1 from public.shifts where staff_id = auth.uid() and shift_date = a.shift_date and status in ('assigned', 'confirmed', 'late')) then raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.shifts where staff_id = r.staff_id and shift_date = b.shift_date and status in ('assigned', 'confirmed', 'late')) then raise exception 'They''re already working on your day.'; end if;
  select skill into sa from public.profiles where id = r.staff_id;
  select skill into sb from public.profiles where id = auth.uid();
  if not public.can_do_job(sb, a.job) or not public.can_do_job(sa, b.job) then raise exception 'You can''t both do each other''s jobs.'; end if;
  update public.swap_offers set status = 'withdrawn' where request_id = req and staff_id = auth.uid() and status = 'passed';
  insert into public.swap_offers (request_id, shift_id, staff_id) values (req, b.id, auth.uid()) returning id into new_id;
  return new_id;
exception when unique_violation then raise exception 'You''ve already answered this one.';
end $$;
grant execute on function public.staff_offer_swap(bigint, bigint) to authenticated;

create or replace function public.staff_pass_swap(req bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.swap_offers (request_id, staff_id, status) values (req, auth.uid(), 'passed');
exception when unique_violation then null;
end $$;
grant execute on function public.staff_pass_swap(bigint) to authenticated;

create or replace function public.staff_withdraw_swap_offer(offer bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.swap_offers set status = 'withdrawn' where id = offer and staff_id = auth.uid() and status = 'offered';
  if not found then raise exception 'That offer has already been answered.'; end if;
end $$;
grant execute on function public.staff_withdraw_swap_offer(bigint) to authenticated;

-- The person who asked picks one offer. It then goes to the manager (Swaps to approve).
create or replace function public.staff_accept_swap_offer(offer bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.swap_offers; r public.swap_requests; a public.shifts; b public.shifts;
begin
  select * into o from public.swap_offers where id = offer for update;
  select * into r from public.swap_requests where id = o.request_id for update;
  if o.id is null or r.staff_id <> auth.uid() then raise exception 'Offer not found.'; end if;
  if r.status <> 'open' or o.status <> 'offered' then raise exception 'That offer is no longer open.'; end if;
  select * into a from public.shifts where id = r.shift_id;
  select * into b from public.shifts where id = o.shift_id;
  if a.staff_id <> r.staff_id or b.staff_id <> o.staff_id or a.status not in ('assigned', 'confirmed') or b.status not in ('assigned', 'confirmed') then
    update public.swap_offers set status = 'declined' where id = o.id;
    raise exception 'The rota has changed, so that offer can''t be used.';
  end if;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note, status)
  values (a.id, b.id, r.staff_id, o.staff_id, r.note, 'accepted');
  update public.swap_offers set status = case when id = o.id then 'accepted' else 'declined' end where request_id = r.id and status = 'offered';
  update public.swap_requests set status = 'matched', decided_at = now() where id = r.id;
end $$;
grant execute on function public.staff_accept_swap_offer(bigint) to authenticated;

-- Holiday: only for days whose rota isn't out yet (once it's out, swap your shifts instead)
create or replace function public.staff_request_holiday(want date[], why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare picked date[]; yr int; n int; clash date; new_id bigint;
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can book holiday.'; end if;
  picked := array(select distinct d from unnest(want) d where d is not null order by d);
  if cardinality(picked) = 0 then raise exception 'Pick at least one day.'; end if;
  if picked[1] < current_date then raise exception 'Pick today or later.'; end if;
  select d into clash from unnest(picked) d where public.rota_published(d) limit 1;
  if clash is not null then raise exception 'The rota for % is already out. Swap your shifts instead.', to_char(clash, 'Dy DD Mon'); end if;
  select d into clash from public.holiday_requests h, unnest(h.days) d
   where h.staff_id = auth.uid() and h.status in ('pending', 'approved') and d = any(picked) limit 1;
  if clash is not null then raise exception 'You already have holiday booked or asked for on %.', to_char(clash, 'Dy DD Mon'); end if;
  for yr, n in select extract(year from d)::int, count(*) from unnest(picked) d group by 1 loop
    if public.holiday_days_taken(auth.uid(), yr) + n > 28 then
      raise exception 'That would go over your 28 days for %. You have % left.', yr, greatest(0, 28 - public.holiday_days_taken(auth.uid(), yr));
    end if;
  end loop;
  insert into public.holiday_requests (staff_id, days, note) values (auth.uid(), picked, nullif(trim(why), '')) returning id into new_id;
  return new_id;
end $$;
grant execute on function public.staff_request_holiday(date[], text) to authenticated;
