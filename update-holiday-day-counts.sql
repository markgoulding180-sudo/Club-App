-- Holiday: show staff "Hol 1 left" on days where 1 person is already off or has asked off (no names, just the count),
-- so they know there's one space left and to be quick. Run after update-holiday-offer-days.sql. Safe to run again.
create or replace function public.holiday_day_counts(d1 date, d2 date)
returns table (day date, off int) language sql stable security definer set search_path = '' as $$
  select d, count(distinct h.staff_id)::int
  from public.holiday_requests h,
       unnest(case when h.status = 'pending' and h.offer_days is not null then h.offer_days else h.days end) d
  where h.status in ('pending', 'approved') and d between d1 and d2 and h.staff_id <> auth.uid()
  group by d;
$$;
grant execute on function public.holiday_day_counts(date, date) to authenticated;
select 'Holiday day counts ready' as done;
