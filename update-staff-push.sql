-- Phone notifications for staff: rota published, swap offers and requests, the manager's decisions
-- (swaps, holiday, can't work) and the manager's replies. Run after add-push-notifications.sql. Safe to run again.

alter table public.push_queue drop constraint if exists push_queue_kind_check;
alter table public.push_queue add constraint push_queue_kind_check check (kind in ('events', 'news', 'bookings', 'messages', 'reminders', 'shifts'));

create or replace function public.push_to(uid uuid, t text, b text, u text default '/?go=hub') returns void
language sql security definer set search_path = '' as $$
  insert into public.push_queue (kind, audience, user_id, title, body, url) values ('shifts', 'user', uid, t, coalesce(b, ''), u);
$$;
create or replace function public.push_shift_txt(sid bigint) returns text
language sql stable security definer set search_path = '' as $$
  select case s.job when 'door' then 'Door' when 'event' then 'Function Room Bar' else 'Lounge Bar' end || ' ' || trim(to_char(s.shift_date, 'Dy FMDD Mon'))
  from public.shifts s where s.id = sid $$;
create or replace function public.push_first(uid uuid) returns text
language sql stable security definer set search_path = '' as $$ select coalesce(first_name, 'A colleague') from public.profiles where id = uid $$;

-- Rota published: every member of staff
create or replace function public.push_on_rota() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.published_at is not null and (tg_op = 'INSERT' or old.published_at is null) then
    insert into public.push_queue (kind, audience, title, body, url)
    values ('shifts', 'staff', '📅 The new rota is out', 'Rota from ' || trim(to_char(new.start_date, 'Dy FMDD Mon')) || '. Tap to see your shifts.', '/?go=myshifts');
  end if; return new;
end $$;
drop trigger if exists push_on_rota on public.rota_periods;
create trigger push_on_rota after insert or update of published_at on public.rota_periods for each row execute function public.push_on_rota();

-- Someone asks everyone for a swap: every other member of staff
create or replace function public.push_on_swap_request() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.push_queue (kind, audience, user_id, title, body, url)
  select 'shifts', 'user', p.id, '🙋 ' || public.push_first(new.staff_id) || ' needs a swap', public.push_shift_txt(new.shift_id) || '. Can you help?', '/?go=swaps'
  from public.profiles p where p.role = 'staff' and p.id <> new.staff_id;
  return new;
end $$;
drop trigger if exists push_on_swap_request on public.swap_requests;
create trigger push_on_swap_request after insert on public.swap_requests for each row execute function public.push_on_swap_request();

-- A colleague offers a shift for your swap
create or replace function public.push_on_swap_offer() returns trigger language plpgsql security definer set search_path = '' as $$
declare r public.swap_requests;
begin
  if new.status = 'offered' and new.shift_id is not null then
    select * into r from public.swap_requests where id = new.request_id;
    perform public.push_to(r.staff_id, '🔄 ' || public.push_first(new.staff_id) || ' offered to swap',
      'Their ' || public.push_shift_txt(new.shift_id) || ' for your ' || public.push_shift_txt(r.shift_id) || '. Tap to pick.', '/?go=swaps');
  end if; return new;
end $$;
drop trigger if exists push_on_swap_offer on public.swap_offers;
create trigger push_on_swap_offer after insert on public.swap_offers for each row execute function public.push_on_swap_offer();

-- Swaps: asked directly, approved or refused by the manager
create or replace function public.push_on_swap() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.status = 'asked' then
    perform public.push_to(new.to_staff, '🔄 ' || public.push_first(new.from_staff) || ' wants to swap with you', public.push_shift_txt(new.from_shift) || '. Tap to answer.', '/?go=swaps');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'approved' then
      perform public.push_to(new.from_staff, '✅ Swapped', 'You now work ' || public.push_shift_txt(new.to_shift) || ' instead.', '/?go=myshifts');
      perform public.push_to(new.to_staff, '✅ Swapped', 'You now work ' || public.push_shift_txt(new.from_shift) || ' instead.', '/?go=myshifts');
    elsif new.status = 'refused' then
      perform public.push_to(new.from_staff, '❌ Swap not approved', 'The manager said no to your swap with ' || public.push_first(new.to_staff) || '.', '/?go=swaps');
      perform public.push_to(new.to_staff, '❌ Swap not approved', 'The manager said no to the swap with ' || public.push_first(new.from_staff) || '.', '/?go=swaps');
    end if;
  end if; return new;
end $$;
drop trigger if exists push_on_swap on public.shift_swaps;
create trigger push_on_swap after insert or update of status on public.shift_swaps for each row execute function public.push_on_swap();

-- Holiday approved or declined
create or replace function public.push_on_holiday() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('approved', 'declined') and new.status is distinct from old.status then
    perform public.push_to(new.staff_id, case when new.status = 'approved' then '🌴 Holiday approved' else '❌ Holiday declined' end,
      trim(to_char((select min(d) from unnest(new.days) d), 'Dy FMDD Mon')) || case when cardinality(new.days) > 1 then ' – ' || trim(to_char((select max(d) from unnest(new.days) d), 'Dy FMDD Mon')) else '' end
      || coalesce('. ' || new.admin_note, ''), '/?go=myshifts');
  end if; return new;
end $$;
drop trigger if exists push_on_holiday on public.holiday_requests;
create trigger push_on_holiday after update of status on public.holiday_requests for each row execute function public.push_on_holiday();

-- Can't work: the manager's decision
create or replace function public.push_on_cantwork() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.decision is distinct from old.decision and new.decision is not null then
    perform public.push_to(new.staff_id, case when new.decision = 'approved' then '✅ You’re off that shift' else '❌ Can’t-work request declined' end,
      public.push_shift_txt(new.id) || case when new.decision = 'approved' then '. The manager approved it.' else '. You’re still on it.' end, '/?go=myshifts');
  end if; return new;
end $$;
drop trigger if exists push_on_cantwork on public.shifts;
create trigger push_on_cantwork after update of decision on public.shifts for each row execute function public.push_on_cantwork();

-- The manager replies to a staff message
create or replace function public.push_on_staff_reply() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.reply is not null and new.reply is distinct from old.reply then
    perform public.push_to(new.staff_id, '💬 The manager replied', left(new.reply, 140), '/?go=hub');
  end if; return new;
end $$;
drop trigger if exists push_on_staff_reply on public.staff_messages;
create trigger push_on_staff_reply after update of reply on public.staff_messages for each row execute function public.push_on_staff_reply();

select 'Staff phone notifications are set up' as done;
