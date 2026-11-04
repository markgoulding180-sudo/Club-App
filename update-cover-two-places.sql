-- Cover requests for more than one place (e.g. Function Room Bar 1 and 2): one request asks for 2 people,
-- and it stays open until both are given the shift. Run after update-cover-push.sql. Safe to run again.
alter table public.cover_calls add column if not exists needed int not null default 1;
alter table public.cover_calls drop constraint if exists cover_calls_needed_check;
alter table public.cover_calls add constraint cover_calls_needed_check check (needed between 1 and 10);

create or replace function public.admin_decide_offer(offer_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.shift_offers; cw bigint; call public.cover_calls;
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into o from public.shift_offers where id = offer_id for update;
  if o.id is null or o.status <> 'offered' then raise exception 'That offer has already been dealt with.'; end if;
  if not yes then update public.shift_offers set status = 'declined', decided_at = now() where id = o.id; return; end if;
  insert into public.shifts (shift_date, session, job, staff_id) values (o.shift_date, o.session, o.job, o.staff_id);
  select id into cw from public.shifts where shift_date = o.shift_date and session = o.session and job = o.job
     and status in ('cannot_work', 'sick', 'no_show') and not covered order by id limit 1;
  if cw is not null then update public.shifts set covered = true, decision = coalesce(decision, case when status = 'cannot_work' then 'approved' end), decided_at = now() where id = cw; end if;
  update public.shift_offers set status = 'accepted', decided_at = now() where id = o.id;
  select * into call from public.cover_calls where shift_date = o.shift_date and session = o.session and job = o.job and status = 'open' for update;
  if call.id is not null and call.needed > 1 then
    -- More places still to fill: keep asking, keep the other offers
    update public.cover_calls set needed = needed - 1 where id = call.id;
  else
    update public.shift_offers set status = 'declined', decided_at = now()
     where shift_date = o.shift_date and session = o.session and job = o.job and status = 'offered' and id <> o.id;
    update public.cover_calls set status = 'filled' where id = call.id;
  end if;
end $$;
grant execute on function public.admin_decide_offer(bigint, boolean) to authenticated;
select 'Cover for two places ready' as done;
