-- Approve only some days of a holiday request (e.g. the free days), and decline the rest with a message.
-- The request keeps the approved days; the other days are kept on record as a declined request. Safe to run again.
create or replace function public.admin_approve_some_days(req bigint, keep date[], why text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.holiday_requests; rest date[];
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into r from public.holiday_requests where id = req for update;
  if r.id is null then raise exception 'Request not found.'; end if;
  if r.status <> 'pending' then raise exception 'That request has already been answered.'; end if;
  keep := array(select d from unnest(keep) d where d = any(r.days) order by d);
  if cardinality(keep) = 0 then raise exception 'Pick at least one day to approve.'; end if;
  rest := array(select d from unnest(r.days) d where not d = any(keep) order by d);
  -- the days not approved, kept on record as declined (no alert to the bosses for this)
  if cardinality(rest) > 0 then
    insert into public.holiday_requests (staff_id, days, note, status, admin_note, decided_by, decided_at)
    values (r.staff_id, rest, r.note, 'declined', nullif(trim(why), ''), auth.uid(), now());
  end if;
  update public.holiday_requests set days = keep where id = req;
  perform public.admin_decide_holiday(req, 'approved',
    'Approved: ' || (select string_agg(trim(to_char(d, 'Dy FMDD Mon')), ', ') from unnest(keep) d)
    || case when cardinality(rest) > 0 then '. Not approved: ' || (select string_agg(trim(to_char(d, 'Dy FMDD Mon')), ', ') from unnest(rest) d)
         || coalesce(' (' || nullif(trim(why), '') || ')', '') else '' end);
end $$;
grant execute on function public.admin_approve_some_days(bigint, date[], text) to authenticated;

-- Bosses are only alerted about new requests that are waiting, not records the app adds itself
create or replace function public.push_boss_holiday() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'pending' then return new; end if;
  perform public.push_bosses('rota', 'shifts', '🌴 Holiday request from ' || public.push_first(new.staff_id),
    trim(to_char((select min(d) from unnest(new.days) d), 'Dy FMDD Mon')) || case when cardinality(new.days) > 1 then ' – ' || trim(to_char((select max(d) from unnest(new.days) d), 'Dy FMDD Mon')) else '' end
    || ' (' || cardinality(new.days) || ' day' || case when cardinality(new.days) > 1 then 's' else '' end || ')', '/?go=rota');
  return new;
end $$;
select 'Approve some days ready' as done;
