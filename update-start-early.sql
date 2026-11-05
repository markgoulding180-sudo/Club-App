-- "Come in early": the manager can set an earlier start time on one shift (e.g. 16:30 to set up a party),
-- with a short note. The person is told on their phone. Hours count from the early start. Safe to run again.
alter table public.shifts add column if not exists start_early time;
alter table public.shifts add column if not exists early_note text;
alter table public.shifts drop constraint if exists shifts_early_note_len;
alter table public.shifts add constraint shifts_early_note_len check (early_note is null or length(early_note) <= 80);

create or replace function public.push_on_start_early() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.start_early is distinct from old.start_early and new.staff_id is not null and new.shift_date >= current_date
     and public.rota_published(new.shift_date) then
    if new.start_early is not null then
      perform public.push_to(new.staff_id, '⏰ Please come in early: ' || to_char(new.start_early, 'HH24:MI'),
        public.push_shift_txt(new.id) || coalesce(' · ' || nullif(new.early_note, ''), '') || '.', '/?go=myshifts');
    else
      perform public.push_to(new.staff_id, '⏰ Normal start time again', public.push_shift_txt(new.id) || '. No need to come in early.', '/?go=myshifts');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists push_on_start_early on public.shifts;
create trigger push_on_start_early after update of start_early on public.shifts for each row execute function public.push_on_start_early();
select 'Come in early ready' as done;
