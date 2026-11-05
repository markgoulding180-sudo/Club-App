-- Cleaning doesn't count as "already working that day" for swaps and for offering to cover a shift.
-- (Sam can clean in the morning and still swap or pick up a bar / door shift that day.) Run after update-clean-job.sql. Safe to run again.

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
  if exists (select 1 from public.shifts where staff_id = a.staff_id and shift_date = b.shift_date and status in ('assigned', 'confirmed', 'late') and (job = 'clean') = (b.job = 'clean')) then
    raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.shifts where staff_id = b.staff_id and shift_date = a.shift_date and status in ('assigned', 'confirmed', 'late') and (job = 'clean') = (a.job = 'clean')) then
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

create or replace function public.staff_offer_shift(d date, sess text, j text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare sk text; new_id bigint;
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can do this.'; end if;
  if d < current_date then raise exception 'That shift has gone.'; end if;
  if not public.rota_published(d) then raise exception 'That rota isn''t published yet.'; end if;
  select skill into sk from public.profiles where id = auth.uid();
  if sk is null or not public.can_do_job(sk, j) then raise exception 'You''re not set up to work that job.'; end if;
  if exists (select 1 from public.shifts where staff_id = auth.uid() and shift_date = d and status in ('assigned', 'confirmed', 'late') and (job = 'clean') = (j = 'clean')) then
    raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.staff_unavailability where staff_id = auth.uid() and off_date = d) then
    raise exception 'You''ve marked yourself unavailable that day.'; end if;
  insert into public.shift_offers (shift_date, session, job, staff_id) values (d, sess, j, auth.uid()) returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'You''ve already offered for that shift.';
end $$;

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
  if exists (select 1 from public.shifts where staff_id = auth.uid() and shift_date = a.shift_date and status in ('assigned', 'confirmed', 'late') and (job = 'clean') = (a.job = 'clean')) then raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.shifts where staff_id = r.staff_id and shift_date = b.shift_date and status in ('assigned', 'confirmed', 'late') and (job = 'clean') = (b.job = 'clean')) then raise exception 'They''re already working on your day.'; end if;
  select skill into sa from public.profiles where id = r.staff_id;
  select skill into sb from public.profiles where id = auth.uid();
  if not public.can_do_job(sb, a.job) or not public.can_do_job(sa, b.job) then raise exception 'You can''t both do each other''s jobs.'; end if;
  update public.swap_offers set status = 'withdrawn' where request_id = req and staff_id = auth.uid() and status = 'passed';
  insert into public.swap_offers (request_id, shift_id, staff_id) values (req, b.id, auth.uid()) returning id into new_id;
  return new_id;
exception when unique_violation then raise exception 'You''ve already answered this one.';
end $$;

create or replace function public.do_swap(sw_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare sw public.shift_swaps; a public.shifts; b public.shifts;
begin
  select * into sw from public.shift_swaps where id = sw_id for update;
  select * into a from public.shifts where id = sw.from_shift for update;
  select * into b from public.shifts where id = sw.to_shift for update;
  if a.staff_id <> sw.from_staff or b.staff_id <> sw.to_staff or a.status not in ('assigned', 'confirmed') or b.status not in ('assigned', 'confirmed') then
    update public.shift_swaps set status = 'cancelled', decided_at = now() where id = sw.id;
    raise exception 'The rota has changed, so this swap can''t go ahead.';
  end if;
  if exists (select 1 from public.shifts x where x.staff_id = sw.from_staff and x.shift_date = b.shift_date and x.session = b.session and x.id <> a.id and x.status in ('assigned','confirmed','late') and (x.job = 'clean') = (b.job = 'clean'))
     or exists (select 1 from public.shifts x where x.staff_id = sw.to_staff and x.shift_date = a.shift_date and x.session = a.session and x.id <> b.id and x.status in ('assigned','confirmed','late') and (x.job = 'clean') = (a.job = 'clean')) then
    raise exception 'One of you is already working at that time, so this swap can''t go ahead.';
  end if;
  perform set_config('app.swapping', '1', true);
  update public.shifts set staff_id = case when id = a.id then b.staff_id else a.staff_id end where id in (a.id, b.id);
  perform set_config('app.swapping', '', true);
  update public.shift_swaps set status = 'approved', decided_at = now() where id = sw.id;
end $$;

select 'Cleaning checks ready' as done;
