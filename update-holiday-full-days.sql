-- Holiday: first come, first served. When 2 people have already asked for a day off (waiting or approved), that day is FULL:
-- staff see it as FULL on their Book holiday calendar and can't ask for it. (The manager can still approve anything.)
-- Run after update-holiday-some-days.sql. Safe to run again.

-- Days in a range that are full (no names, so staff only see that the day is full)
create or replace function public.holiday_full_days(d1 date, d2 date)
returns table (day date, off int) language sql stable security definer set search_path = '' as $$
  select d, count(distinct h.staff_id)::int
  from public.holiday_requests h, unnest(h.days) d
  where h.status in ('pending', 'approved') and d between d1 and d2 and h.staff_id <> auth.uid()
  group by d having count(distinct h.staff_id) >= 2;
$$;
grant execute on function public.holiday_full_days(date, date) to authenticated;

create or replace function public.staff_request_holiday(want date[], why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare picked date[]; yr int; n int; clash date; new_id bigint;
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can book holiday.'; end if;
  picked := array(select distinct d from unnest(want) d where d is not null order by d);
  if cardinality(picked) = 0 then raise exception 'Pick at least one day.'; end if;
  if picked[1] < current_date then raise exception 'Pick today or later.'; end if;
  select d into clash from unnest(picked) d where public.rota_published(d) limit 1;
  if clash is not null then raise exception 'The rota for % is already out. Swap your shifts instead.', to_char(clash, 'Dy DD Mon'); end if;
  select d into clash from public.holiday_requests h, unnest(h.days) d
   where h.staff_id = auth.uid() and h.status in ('pending', 'approved') and d = any(picked) limit 1;
  if clash is not null then raise exception 'You already have holiday booked or asked for on %.', to_char(clash, 'Dy DD Mon'); end if;
  -- first come, first served: 2 people already off = full
  select f.day into clash from public.holiday_full_days(picked[1], picked[cardinality(picked)]) f where f.day = any(picked) limit 1;
  if clash is not null then raise exception '% is full: 2 people have already asked for it off. Please pick other days.', to_char(clash, 'Dy DD Mon'); end if;
  for yr, n in select extract(year from d)::int, count(*) from unnest(picked) d group by 1 loop
    if public.holiday_days_taken(auth.uid(), yr) + n > 28 then
      raise exception 'That would go over your 28 days for %. You have % left.', yr, greatest(0, 28 - public.holiday_days_taken(auth.uid(), yr));
    end if;
  end loop;
  insert into public.holiday_requests (staff_id, days, note) values (auth.uid(), picked, nullif(trim(why), '')) returning id into new_id;
  return new_id;
end $$;
grant execute on function public.staff_request_holiday(date[], text) to authenticated;
select 'Full holiday days ready' as done;
