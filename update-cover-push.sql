-- Cover calls: when the manager presses "📣 Ask everyone", staff who could work it get a phone notification;
-- when someone says "Yes, I can work it", the manager gets one; if the manager picks someone else, the others are told.
-- Run after update-staff-push.sql and update-boss-push.sql. Safe to run again.

create or replace function public.push_on_cover_call() returns trigger language plpgsql security definer set search_path = '' as $$
declare txt text := case new.job when 'door' then 'Door' when 'event' then 'Function Room Bar' else 'Lounge Bar' end || ' '
  || case new.session when 'day' then 'daytime' else 'evening' end || ', ' || trim(to_char(new.shift_date, 'Dy FMDD Mon'));
begin
  if new.status = 'open' then
    insert into public.push_queue (kind, audience, user_id, title, body, url)
    select 'shifts', 'user', p.id, '📣 Cover needed: can you work?', txt || '. Tap Yes or No.', '/?go=swaps'
    from public.profiles p
    where p.role = 'staff' and public.can_do_job(p.skill, new.job)
      and not exists (select 1 from public.shifts x where x.staff_id = p.id and x.shift_date = new.shift_date and x.status in ('assigned','confirmed','late','cannot_work'))
      and not exists (select 1 from public.staff_unavailability u where u.staff_id = p.id and u.off_date = new.shift_date);
  end if; return new;
end $$;
drop trigger if exists push_on_cover_call on public.cover_calls;
create trigger push_on_cover_call after insert on public.cover_calls for each row execute function public.push_on_cover_call();

create or replace function public.push_on_shift_offer() returns trigger language plpgsql security definer set search_path = '' as $$
declare txt text;
begin
  txt := case coalesce(new.job, old.job) when 'door' then 'Door' when 'event' then 'Function Room Bar' else 'Lounge Bar' end || ' '
    || case coalesce(new.session, old.session) when 'day' then 'daytime' else 'evening' end || ', ' || trim(to_char(coalesce(new.shift_date, old.shift_date), 'Dy FMDD Mon'));
  if tg_op = 'INSERT' and new.status = 'offered' then
    perform public.push_bosses('rota', 'shifts', '🙋 ' || public.push_first(new.staff_id) || ' can work', txt || '. Tap to accept.', '/?go=rota');
  elsif tg_op = 'UPDATE' and old.status = 'offered' and new.status = 'declined' then
    perform public.push_to(new.staff_id, 'Cover sorted, thanks for offering', 'Someone else is working ' || txt || '.', '/?go=myshifts');
  end if; return new;
end $$;
drop trigger if exists push_on_shift_offer on public.shift_offers;
create trigger push_on_shift_offer after insert or update of status on public.shift_offers for each row execute function public.push_on_shift_offer();

select 'done' as result;
