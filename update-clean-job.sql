-- Cleaning: a new job on the rota, every morning 08:00–11:00 (1 cleaner a day).
-- A new skill "Cleaning only" for the cleaner (Mandy). Anyone else can be put on cleaning too (Sam and Adam clean some days).
-- Cleaning doesn't count as "a shift that day": someone can clean in the morning and work the bar or door later.
-- Run once. Safe to run again.

-- Jobs: allow 'clean'
do $$
declare r record;
begin
  for r in select c.conrelid::regclass as t, c.conname from pg_constraint c
           where c.contype = 'c' and c.conrelid in ('public.shifts'::regclass, 'public.shift_offers'::regclass, 'public.cover_calls'::regclass)
             and pg_get_constraintdef(c.oid) ilike '%job%' loop
    execute format('alter table %s drop constraint %I', r.t, r.conname);
  end loop;
  for r in select c.conname from pg_constraint c
           where c.contype = 'c' and c.conrelid = 'public.profiles'::regclass and pg_get_constraintdef(c.oid) ilike '%skill%' loop
    execute format('alter table public.profiles drop constraint %I', r.conname);
  end loop;
end $$;
alter table public.shifts       add constraint shifts_job_check       check (job in ('lounge', 'event', 'door', 'clean'));
alter table public.shift_offers add constraint shift_offers_job_check check (job in ('lounge', 'event', 'door', 'clean'));
alter table public.cover_calls  add constraint cover_calls_job_check  check (job in ('lounge', 'event', 'door', 'clean'));
alter table public.profiles     add constraint profiles_skill_check   check (skill in ('bar', 'door', 'both', 'clean'));

-- Who can do which job: anyone can clean; a "cleaning only" person only cleans
create or replace function public.can_do_job(skill text, job text) returns boolean
language sql immutable set search_path = '' as $$
  select case when job = 'clean' then true
              when skill = 'clean' then false
              else coalesce(skill, 'both') = 'both' or (skill = 'door' and job = 'door') or (skill = 'bar' and job in ('lounge', 'event')) end $$;

-- Regular shifts can include cleaning (daytime only)
create or replace function public.admin_set_regular(pid uuid, pattern jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can set regular shifts.'; end if;
  if jsonb_typeof(pattern) <> 'array' or jsonb_array_length(pattern) > 21 then raise exception 'That pattern isn''t valid.'; end if;
  if exists (select 1 from jsonb_array_elements(pattern) x
             where (x->>'d') !~ '^[0-6]$' or x->>'s' not in ('day', 'eve') or x->>'j' not in ('lounge', 'event', 'door', 'clean')
                or (x->>'j' = 'clean' and x->>'s' <> 'day')) then
    raise exception 'That pattern isn''t valid.';
  end if;
  update public.profiles set regular_shifts = pattern where id = pid;
end $$;
grant execute on function public.admin_set_regular(uuid, jsonb) to authenticated;

-- One shift per session each, but cleaning is counted separately (clean in the morning, then the daytime bar)
drop index if exists public.shifts_one_per_session;
create unique index shifts_one_per_session on public.shifts (shift_date, session, staff_id, (job = 'clean'))
  where status in ('assigned', 'confirmed', 'late');

-- One shift a day, but cleaning is separate: you can clean and also work the bar or door that day
create or replace function public.shifts_one_a_day()
returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('app.swapping', true), '') = '1' then return new; end if;
  if new.status in ('assigned', 'confirmed', 'late') and exists (
    select 1 from public.shifts o
    where o.staff_id = new.staff_id and o.shift_date = new.shift_date and o.id <> new.id
      and o.status in ('assigned', 'confirmed', 'late')
      and (o.job = 'clean') = (new.job = 'clean')) then
    raise exception 'They are already working that day.';
  end if;
  return new;
end $$;

select 'Cleaning job ready' as done;
