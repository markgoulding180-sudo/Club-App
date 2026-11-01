-- Phone notifications for the bosses: new holiday requests, can't-work requests, booking requests,
-- messages from staff, and (for info) swaps that staff have done.
-- Run after update-staff-push.sql. Safe to run again.

-- Bosses who look after an area (App admin = everything; no areas set = everything)
create or replace function public.bosses_for(area text) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p
  where p.role = 'admin' and ('owner' = any(p.perms)
     or not (p.perms && array['bookings','rota','staff','tickets','whatson','messages','register','notices','jobs'])
     or area = any(p.perms));
$$;
create or replace function public.push_bosses(area text, k text, t text, b text, u text) returns void
language sql security definer set search_path = '' as $$
  insert into public.push_queue (kind, audience, user_id, title, body, url)
  select k, 'user', x.uid, t, coalesce(b, ''), u from public.bosses_for(area) as x(uid);
$$;

-- New holiday request
create or replace function public.push_boss_holiday() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.push_bosses('rota', 'shifts', '🌴 Holiday request from ' || public.push_first(new.staff_id),
    trim(to_char((select min(d) from unnest(new.days) d), 'Dy FMDD Mon')) || case when cardinality(new.days) > 1 then ' – ' || trim(to_char((select max(d) from unnest(new.days) d), 'Dy FMDD Mon')) else '' end
    || ' (' || cardinality(new.days) || ' day' || case when cardinality(new.days) > 1 then 's' else '' end || ')', '/?go=rota');
  return new;
end $$;
drop trigger if exists push_boss_holiday on public.holiday_requests;
create trigger push_boss_holiday after insert on public.holiday_requests for each row execute function public.push_boss_holiday();

-- Staff says they can't work a shift
create or replace function public.push_boss_cantwork() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'cannot_work' and old.status is distinct from 'cannot_work' then
    perform public.push_bosses('rota', 'shifts', '⚠️ ' || public.push_first(new.staff_id) || ' can’t work',
      public.push_shift_txt(new.id) || coalesce(': ' || left(new.reason, 100), ''), '/?go=rota');
  end if; return new;
end $$;
drop trigger if exists push_boss_cantwork on public.shifts;
create trigger push_boss_cantwork after update of status on public.shifts for each row execute function public.push_boss_cantwork();

-- New booking request from a member
create or replace function public.push_boss_booking() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.booking_kind = 'member' and new.status = 'pending' then
    perform public.push_bosses('bookings', 'bookings', '📅 New booking request',
      coalesce(new.first_name || ' ' || new.last_name, 'A member') || ': ' || coalesce(new.event_type, 'booking') || ', '
      || case new.room when 'hall' then 'Function Room' else 'Lounge Bar' end || ' ' || trim(to_char(new.booking_date, 'Dy FMDD Mon')), '/?go=bookings');
  end if; return new;
end $$;
drop trigger if exists push_boss_booking on public.bookings;
create trigger push_boss_booking after insert on public.bookings for each row execute function public.push_boss_booking();

-- Message from staff
create or replace function public.push_boss_staffmsg() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.push_bosses('messages', 'messages', '✉️ ' || public.push_first(new.staff_id) || ': ' ||
    case new.topic when 'cant_work' then 'can’t work a shift' when 'ill' then 'feeling ill' when 'club_problem' then 'problem at the club'
      when 'abuse' then 'abuse from a member or guest' when 'complaint' then 'complaint' else 'message' end,
    left(new.body, 140), '/?go=messages');
  return new;
end $$;
drop trigger if exists push_boss_staffmsg on public.staff_messages;
create trigger push_boss_staffmsg after insert on public.staff_messages for each row execute function public.push_boss_staffmsg();

-- Swap done (for info)
create or replace function public.push_boss_swap() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    perform public.push_bosses('rota', 'shifts', '🔄 ' || public.push_first(new.from_staff) || ' and ' || public.push_first(new.to_staff) || ' swapped',
      public.push_first(new.from_staff) || ' now works ' || public.push_shift_txt(new.to_shift) || ', ' || public.push_first(new.to_staff) || ' works ' || public.push_shift_txt(new.from_shift) || '.', '/?go=swaplog');
  end if; return new;
end $$;
drop trigger if exists push_boss_swap on public.shift_swaps;
create trigger push_boss_swap after update of status on public.shift_swaps for each row execute function public.push_boss_swap();

select first_name, title from public.profiles where id in (select public.bosses_for('rota')) order by title;
