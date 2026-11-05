-- Holiday: when only some days can be approved, the manager OFFERS those days and the staff member decides.
-- "Only Thu 26 Nov can be approved (2 people are already off on Fri 27 and Sat 28). Do you still want Thu 26?"
--   Yes  -> the offered days are approved, the rest are kept on record as not approved.
--   No   -> the whole request is withdrawn (and the days are free again for others).
-- While waiting for the answer, only the offered days count towards the "2 off" limit.
-- Run after update-holiday-some-days.sql and update-holiday-full-days.sql. Safe to run again.

alter table public.holiday_requests add column if not exists offer_days date[];
alter table public.holiday_requests add column if not exists offer_note text;
alter table public.holiday_requests add column if not exists offered_at timestamptz;

create or replace function public.hol_days_txt(ds date[]) returns text language sql immutable set search_path = '' as $$
  select string_agg(trim(to_char(d, 'Dy FMDD Mon')), ', ' order by d) from unnest(ds) d
$$;

-- Manager: offer only some days of a request
create or replace function public.admin_offer_some_days(req bigint, keep date[], why text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.holiday_requests;
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into r from public.holiday_requests where id = req for update;
  if r.id is null then raise exception 'Request not found.'; end if;
  if r.status <> 'pending' then raise exception 'That request has already been answered.'; end if;
  keep := array(select distinct d from unnest(keep) d where d = any(r.days) order by d);
  if cardinality(keep) = 0 then raise exception 'Tick at least one day, or use Decline.'; end if;
  if cardinality(keep) = cardinality(r.days) then raise exception 'You ticked every day: use Approve instead.'; end if;
  update public.holiday_requests set offer_days = keep, offer_note = nullif(trim(why), ''), offered_at = now() where id = req;
  perform public.push_to(r.staff_id, '🌴 Your holiday: only some days can be approved',
    'Only ' || public.hol_days_txt(keep) || ' can be approved' || coalesce(' (' || nullif(trim(why), '') || ')', '')
    || '. Tap to say if you still want ' || case when cardinality(keep) > 1 then 'them' else 'it' end || '.', '/?go=myshifts');
end $$;
grant execute on function public.admin_offer_some_days(bigint, date[], text) to authenticated;

-- Staff: answer the offer
create or replace function public.staff_answer_holiday_offer(req bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.holiday_requests; rest date[];
begin
  select * into r from public.holiday_requests where id = req and staff_id = auth.uid() for update;
  if r.id is null then raise exception 'Request not found.'; end if;
  if r.status <> 'pending' or r.offer_days is null then raise exception 'This has already been sorted. Please refresh.'; end if;
  if yes then
    rest := array(select d from unnest(r.days) d where not d = any(r.offer_days) order by d);
    if cardinality(rest) > 0 then
      insert into public.holiday_requests (staff_id, days, note, status, admin_note, decided_by, decided_at)
      values (r.staff_id, rest, r.note, 'declined', r.offer_note, null, now());
    end if;
    update public.holiday_requests set days = r.offer_days, status = 'approved', offer_days = null,
      admin_note = 'You said yes to ' || public.hol_days_txt(r.offer_days), decided_at = now() where id = req;
    insert into public.staff_unavailability (staff_id, off_date, reason, holiday_id)
      select r.staff_id, d, 'Holiday', r.id from unnest(r.offer_days) d
    on conflict (staff_id, off_date) do nothing;
    update public.shifts set status = 'cannot_work', reason = 'Holiday'
     where staff_id = r.staff_id and shift_date = any(r.offer_days) and status in ('assigned', 'confirmed');
    perform public.push_bosses('rota', 'shifts', '🌴 ' || public.push_first(r.staff_id) || ' said yes',
      'Holiday booked: ' || public.hol_days_txt(r.offer_days) || '.', '/?go=rota');
  else
    update public.holiday_requests set status = 'cancelled', offer_days = null, decided_at = now() where id = req;
    perform public.push_bosses('rota', 'shifts', '🌴 ' || public.push_first(r.staff_id) || ' said no thanks',
      'They don''t want ' || public.hol_days_txt(r.offer_days) || ' on its own. The request is withdrawn.', '/?go=rota');
  end if;
end $$;
grant execute on function public.staff_answer_holiday_offer(bigint, boolean) to authenticated;

-- FULL days: count only the offered days of a request that is waiting on the staff member
create or replace function public.holiday_full_days(d1 date, d2 date)
returns table (day date, off int) language sql stable security definer set search_path = '' as $$
  select d, count(distinct h.staff_id)::int
  from public.holiday_requests h,
       unnest(case when h.status = 'pending' and h.offer_days is not null then h.offer_days else h.days end) d
  where h.status in ('pending', 'approved') and d between d1 and d2 and h.staff_id <> auth.uid()
  group by d having count(distinct h.staff_id) >= 2;
$$;
grant execute on function public.holiday_full_days(date, date) to authenticated;

select 'Offer some days ready' as done;
