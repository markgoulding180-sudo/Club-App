-- Swaps no longer need the manager: when staff agree, the rota changes straight away.
-- Run after update-swap-board.sql (and update-staff-push.sql if you've run it). Safe to run again.

-- Swap two shifts over (used by both kinds of swap)
create or replace function public.do_swap(sw_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare sw public.shift_swaps; a public.shifts; b public.shifts;
begin
  select * into sw from public.shift_swaps where id = sw_id for update;
  select * into a from public.shifts where id = sw.from_shift for update;
  select * into b from public.shifts where id = sw.to_shift for update;
  if a.staff_id <> sw.from_staff or b.staff_id <> sw.to_staff or a.status not in ('assigned', 'confirmed') or b.status not in ('assigned', 'confirmed') then
    update public.shift_swaps set status = 'cancelled', decided_at = now() where id = sw.id;
    raise exception 'The rota has changed, so this swap can''t go ahead.';
  end if;
  if exists (select 1 from public.shifts x where x.staff_id = sw.from_staff and x.shift_date = b.shift_date and x.session = b.session and x.id <> a.id and x.status in ('assigned','confirmed','late'))
     or exists (select 1 from public.shifts x where x.staff_id = sw.to_staff and x.shift_date = a.shift_date and x.session = a.session and x.id <> b.id and x.status in ('assigned','confirmed','late')) then
    raise exception 'One of you is already working at that time, so this swap can''t go ahead.';
  end if;
  perform set_config('app.swapping', '1', true);
  update public.shifts set staff_id = case when id = a.id then b.staff_id else a.staff_id end where id in (a.id, b.id);
  perform set_config('app.swapping', '', true);
  update public.shift_swaps set status = 'approved', decided_at = now() where id = sw.id;
end $$;
revoke all on function public.do_swap(bigint) from public, anon, authenticated;

-- Asked directly: when they say yes, it's done
create or replace function public.staff_answer_swap(swap_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shift_swaps set status = case when yes then 'accepted' else 'declined' end, decided_at = case when yes then null else now() end
  where id = swap_id and to_staff = auth.uid() and status = 'asked';
  if not found then raise exception 'That swap has already been dealt with.'; end if;
  if yes then perform public.do_swap(swap_id); end if;
end $$;
grant execute on function public.staff_answer_swap(bigint, boolean) to authenticated;

-- Swap board: when you pick an offer, it's done
create or replace function public.staff_accept_swap_offer(offer bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.swap_offers; r public.swap_requests; a public.shifts; b public.shifts; sid bigint;
begin
  select * into o from public.swap_offers where id = offer for update;
  select * into r from public.swap_requests where id = o.request_id for update;
  if o.id is null or r.staff_id <> auth.uid() then raise exception 'Offer not found.'; end if;
  if r.status <> 'open' or o.status <> 'offered' then raise exception 'That offer is no longer open.'; end if;
  select * into a from public.shifts where id = r.shift_id;
  select * into b from public.shifts where id = o.shift_id;
  if a.staff_id <> r.staff_id or b.staff_id <> o.staff_id or a.status not in ('assigned', 'confirmed') or b.status not in ('assigned', 'confirmed') then
    update public.swap_offers set status = 'declined' where id = o.id;
    raise exception 'The rota has changed, so that offer can''t be used.';
  end if;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note, status)
  values (a.id, b.id, r.staff_id, o.staff_id, r.note, 'accepted') returning id into sid;
  update public.swap_offers set status = case when id = o.id then 'accepted' else 'declined' end where request_id = r.id and status = 'offered';
  update public.swap_requests set status = 'matched', decided_at = now() where id = r.id;
  perform public.do_swap(sid);
end $$;
grant execute on function public.staff_accept_swap_offer(bigint) to authenticated;

-- Any swaps that were waiting for the manager: put them through now
do $$ declare w record; begin
  for w in select id from public.shift_swaps where status = 'accepted' loop
    begin perform public.do_swap(w.id); exception when others then raise notice 'Swap % skipped: %', w.id, sqlerrm; end;
  end loop;
end $$;

select status, count(*) from public.shift_swaps group by status order by status;
