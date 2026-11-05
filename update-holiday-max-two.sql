-- Holiday: a hard rule in the database. No day can ever have more than 2 people with holiday booked or asked for.
-- It checks every holiday request as it is saved, whoever saves it (staff, manager, or a script),
-- and two people asking at the same moment can't both get the last space (they queue for a lock).
-- Counts: waiting + approved requests. If the manager has offered only some days, only those days count.
-- Withdrawn, declined and cancelled requests don't count, so the space comes back.
-- Run after update-holiday-offer-days.sql. Safe to run again.

create or replace function public.holiday_max_two() returns trigger language plpgsql security definer set search_path = '' as $$
declare full_day date;
begin
  if new.status not in ('pending', 'approved') then return new; end if;
  perform pg_advisory_xact_lock(hashtext('holiday_requests_max_two'));
  select d into full_day
  from unnest(case when new.status = 'pending' and new.offer_days is not null then new.offer_days else new.days end) d
  where (select count(distinct h.staff_id) from public.holiday_requests h,
           unnest(case when h.status = 'pending' and h.offer_days is not null then h.offer_days else h.days end) x
         where h.status in ('pending', 'approved') and x = d) > 2
  limit 1;
  if full_day is not null then
    raise exception '% is full: 2 people already have holiday booked or asked for that day. Please pick other days.', trim(to_char(full_day, 'Dy FMDD Mon'));
  end if;
  return new;
end $$;

drop trigger if exists holiday_max_two on public.holiday_requests;
create constraint trigger holiday_max_two after insert or update of days, offer_days, status on public.holiday_requests
  for each row execute function public.holiday_max_two();

drop trigger if exists holiday_lock on public.holiday_requests;

-- Check: any day already over the limit? (should be none)
select d as day, count(distinct h.staff_id) as people
from public.holiday_requests h, unnest(h.days) d where h.status in ('pending', 'approved')
group by d having count(distinct h.staff_id) > 2 order by d;
