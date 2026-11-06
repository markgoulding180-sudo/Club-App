-- Can't work: friendlier phone alerts for the manager's decision. Safe to run again.
create or replace function public.push_on_cantwork() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.decision is distinct from old.decision and new.decision is not null then
    if new.decision = 'approved' then
      perform public.push_to(new.staff_id, '✅ You’re off that shift', public.push_shift_txt(new.id) || '. The manager has let you off.', '/?go=myshifts');
    else
      perform public.push_to(new.staff_id, '🙏 Sorry, ' || public.push_first(new.staff_id),
        'We couldn’t find anyone to cover ' || public.push_shift_txt(new.id) || ', so we need you to work it. Thank you for understanding.', '/?go=myshifts');
    end if;
  end if; return new;
end $$;
drop trigger if exists push_on_cantwork on public.shifts;
create trigger push_on_cantwork after update of decision on public.shifts for each row execute function public.push_on_cantwork();
select 'Polite can''t-work messages ready' as done;
