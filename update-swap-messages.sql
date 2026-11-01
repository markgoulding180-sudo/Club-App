-- Swap messages, tidied up. Run after update-staff-push.sql and update-swaps-no-approval.sql. Safe to run again.
-- 1) "Needs a swap" only goes to staff who could actually help (free that day, can do that job, and have a shift to offer back).
-- 2) When a swap is done: the person who offered gets "Thanks for swapping", the person who asked gets "Swapped".
-- 3) People whose offer wasn't picked are told, and keep their shift.

create or replace function public.can_do_job(skill text, job text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(skill, 'both') = 'both' or (skill = 'door' and job = 'door') or (skill = 'bar' and job in ('lounge', 'event')) $$;

create or replace function public.push_on_swap_request() returns trigger language plpgsql security definer set search_path = '' as $$
declare a public.shifts; asker public.profiles;
begin
  select * into a from public.shifts where id = new.shift_id;
  select * into asker from public.profiles where id = new.staff_id;
  insert into public.push_queue (kind, audience, user_id, title, body, url)
  select 'shifts', 'user', p.id, '🙋 ' || coalesce(asker.first_name, 'A colleague') || ' needs a swap',
         public.push_shift_txt(a.id) || '. Can you help? Tap to offer one of your shifts.', '/?go=swaps'
  from public.profiles p
  where p.role = 'staff' and p.id <> new.staff_id and public.can_do_job(p.skill, a.job)
    and not exists (select 1 from public.shifts x where x.staff_id = p.id and x.shift_date = a.shift_date and x.status in ('assigned','confirmed','late'))
    and not exists (select 1 from public.staff_unavailability u where u.staff_id = p.id and u.off_date = a.shift_date)
    and exists (select 1 from public.shifts x where x.staff_id = p.id and x.status in ('assigned','confirmed') and x.shift_date > current_date
                and x.shift_date <> a.shift_date and public.rota_published(x.shift_date) and public.can_do_job(asker.skill, x.job)
                and not exists (select 1 from public.shifts y where y.staff_id = new.staff_id and y.shift_date = x.shift_date and y.status in ('assigned','confirmed','late')));
  return new;
end $$;

create or replace function public.push_on_swap() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.status = 'asked' then
    perform public.push_to(new.to_staff, '🔄 ' || public.push_first(new.from_staff) || ' wants to swap with you', public.push_shift_txt(new.from_shift) || '. Tap to answer.', '/?go=swaps');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'approved' then
      perform public.push_to(new.from_staff, '✅ Swapped with ' || public.push_first(new.to_staff), 'You now work ' || public.push_shift_txt(new.to_shift) || ' instead. The rota is updated.', '/?go=myshifts');
      perform public.push_to(new.to_staff, '🤝 Thanks for swapping!', public.push_first(new.from_staff) || ' picked your offer. You now work ' || public.push_shift_txt(new.from_shift) || ' instead.', '/?go=myshifts');
    elsif new.status = 'declined' then
      perform public.push_to(new.from_staff, '❌ ' || public.push_first(new.to_staff) || ' can’t swap', 'You’re still on ' || public.push_shift_txt(new.from_shift) || '. Try asking everyone.', '/?go=swaps');
    end if;
  end if; return new;
end $$;

-- Offer not picked (they chose someone else, or cancelled the request)
create or replace function public.push_on_offer_closed() returns trigger language plpgsql security definer set search_path = '' as $$
declare r public.swap_requests;
begin
  if old.status = 'offered' and new.status = 'declined' and new.shift_id is not null then
    select * into r from public.swap_requests where id = new.request_id;
    perform public.push_to(new.staff_id, 'Swap sorted, thanks for offering',
      public.push_first(r.staff_id) || case when r.status = 'cancelled' then ' doesn’t need the swap any more.' else ' chose a different swap.' end || ' You keep your ' || public.push_shift_txt(new.shift_id) || '.', '/?go=swaps');
  end if; return new;
end $$;
drop trigger if exists push_on_offer_closed on public.swap_offers;
create trigger push_on_offer_closed after update of status on public.swap_offers for each row execute function public.push_on_offer_closed();

select 'Swap messages updated' as done;
