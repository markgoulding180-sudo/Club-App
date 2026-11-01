-- Can't-work requests send one alert to the manager, not two (the staff message no longer sends its own).
create or replace function public.push_boss_staffmsg() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.topic = 'cant_work' then return new; end if;
  perform public.push_bosses('messages', 'messages', '✉️ ' || public.push_first(new.staff_id) || ': ' ||
    case new.topic when 'ill' then 'feeling ill' when 'club_problem' then 'problem at the club'
      when 'abuse' then 'abuse from a member or guest' when 'complaint' then 'complaint' else 'message' end,
    left(new.body, 140), '/?go=messages');
  return new;
end $$;
select 'done' as result;
