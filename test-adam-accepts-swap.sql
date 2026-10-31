-- TEST: Adam picks the swap offer he was sent, so the swap goes to the manager to approve.
-- (Does the same as Adam tapping "Pick this one" in the app.)
do $$
declare adam uuid; o public.swap_offers; r public.swap_requests;
begin
  select id into adam from public.profiles where lower(email) = 'adam@railway.com';
  select o2.* into o from public.swap_offers o2 join public.swap_requests r2 on r2.id = o2.request_id
  where r2.staff_id = adam and r2.status = 'open' and o2.status = 'offered' order by o2.created_at limit 1;
  if o.id is null then raise exception 'Adam has no swap offers waiting. Run test-adam-reply-and-swap.sql first.'; end if;
  select * into r from public.swap_requests where id = o.request_id;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note, status)
  values (r.shift_id, o.shift_id, adam, o.staff_id, r.note, 'accepted');
  update public.swap_offers set status = case when id = o.id then 'accepted' else 'declined' end where request_id = r.id and status = 'offered';
  update public.swap_requests set status = 'matched', decided_at = now() where id = r.id;
end $$;

-- Check: this swap is now waiting for the manager
select p1.first_name || ' (' || s1.job || ' ' || to_char(s1.shift_date, 'Dy DD Mon') || ') swaps with ' || p2.first_name || ' (' || s2.job || ' ' || to_char(s2.shift_date, 'Dy DD Mon') || ')' as waiting_for_manager
from public.shift_swaps w join public.shifts s1 on s1.id = w.from_shift join public.shifts s2 on s2.id = w.to_shift
join public.profiles p1 on p1.id = w.from_staff join public.profiles p2 on p2.id = w.to_staff where w.status = 'accepted';
