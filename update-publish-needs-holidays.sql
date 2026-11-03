-- A rota can't be published while a holiday request in it is still waiting for an answer.
create or replace function public.admin_publish_rota(period_start date, publish boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Only admins can publish the rota.'; end if;
  if period_start <> public.rota_period_start(period_start) then raise exception 'That isn''t the start of a rota.'; end if;
  if publish then
    select count(*) into n from public.holiday_requests h
    where h.status = 'pending' and exists (select 1 from unnest(h.days) d where d between period_start and period_start + 27);
    if n > 0 then raise exception 'Answer the % holiday request% in this rota first.', n, case when n > 1 then 's' else '' end; end if;
  end if;
  insert into public.rota_periods (start_date, published_at, published_by)
  values (period_start, case when publish then now() end, case when publish then auth.uid() end)
  on conflict (start_date) do update set published_at = excluded.published_at, published_by = excluded.published_by;
end $$;
grant execute on function public.admin_publish_rota(date, boolean) to authenticated;
select 'done' as result;
