-- Staff get a phone notification when the manager adds them to, or takes them off, a shift on a published rota.
-- (Swaps and the rota being published have their own messages.) Run after update-staff-push.sql. Safe to run again.
create or replace function public.push_on_shift_change() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(current_setting('app.swapping', true), '') = '1' then return coalesce(new, old); end if;
  if tg_op = 'INSERT' then
    if public.rota_published(new.shift_date) and new.shift_date >= current_date then
      perform public.push_to(new.staff_id, '📅 You’ve been added to a shift', public.push_shift_txt(new.id) || '. Tap to see your shifts.', '/?go=myshifts');
    end if;
  elsif tg_op = 'DELETE' then
    if public.rota_published(old.shift_date) and old.shift_date >= current_date and old.status in ('assigned', 'confirmed') then
      perform public.push_to(old.staff_id, '📅 You’ve been taken off a shift',
        case old.job when 'door' then 'Door' when 'event' then 'Function Room Bar' else 'Lounge Bar' end || ' ' || trim(to_char(old.shift_date, 'Dy FMDD Mon')) || '.', '/?go=myshifts');
    end if;
  elsif tg_op = 'UPDATE' and new.staff_id is distinct from old.staff_id and public.rota_published(new.shift_date) and new.shift_date >= current_date then
    perform public.push_to(new.staff_id, '📅 You’ve been added to a shift', public.push_shift_txt(new.id) || '. Tap to see your shifts.', '/?go=myshifts');
    perform public.push_to(old.staff_id, '📅 You’ve been taken off a shift', public.push_shift_txt(new.id) || '.', '/?go=myshifts');
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists push_on_shift_change on public.shifts;
create trigger push_on_shift_change after insert or delete or update of staff_id on public.shifts for each row execute function public.push_on_shift_change();
select 'done' as result;
