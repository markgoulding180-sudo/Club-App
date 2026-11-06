-- Can't work: remember when the staff member asked, so the manager sees requests in the order they were asked (first at the top).
-- Run once. Safe to run again.
alter table public.shifts add column if not exists asked_off_at timestamptz;
create or replace function public.shifts_asked_off_at() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'cannot_work' and (tg_op = 'INSERT' or old.status is distinct from 'cannot_work') then new.asked_off_at := now(); end if;
  return new;
end $$;
drop trigger if exists shifts_asked_off_at on public.shifts;
create trigger shifts_asked_off_at before insert or update of status on public.shifts for each row execute function public.shifts_asked_off_at();
update public.shifts set asked_off_at = coalesce(decided_at, now()) where status = 'cannot_work' and asked_off_at is null;
select 'Can''t work asked time ready' as done;
