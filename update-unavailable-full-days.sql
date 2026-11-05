-- Staff can't mark themselves unavailable on a Hol FULL day (2 people already off), as that would make 3 off.
-- They're told to speak to the manager instead. Run after update-holiday-full-days.sql. Safe to run again.
create or replace function public.staff_mark_unavailable(d date, why text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can do this.'; end if;
  if d < current_date then raise exception 'Pick today or a later date.'; end if;
  if exists (select 1 from public.holiday_full_days(d, d)) then
    raise exception '% is Hol FULL: 2 people are already off that day, so you can''t mark yourself unavailable. Please speak to the manager.', trim(to_char(d, 'Dy FMDD Mon'));
  end if;
  insert into public.staff_unavailability (staff_id, off_date, reason) values (auth.uid(), d, why);
  update public.shifts set status = 'cannot_work', reason = coalesce(why, 'Marked as can''t work')
  where staff_id = auth.uid() and shift_date = d and status in ('assigned', 'confirmed');
exception when unique_violation then
  raise exception 'You have already marked that day.';
end $$;
grant execute on function public.staff_mark_unavailable(date, text) to authenticated;
select 'Unavailable blocked on FULL days' as done;
