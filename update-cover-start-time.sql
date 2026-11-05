-- Start time on a cover request: the manager can ask for someone to come in early (e.g. 15:00 instead of 17:00)
-- when asking everyone, or change it afterwards. Staff see the real time before they say yes, and the early start
-- goes onto the rota with the shift. Run after update-cover-two-places.sql and update-start-early.sql. Safe to run again.
alter table public.cover_calls add column if not exists start_early time;
alter table public.cover_calls add column if not exists early_note text;
alter table public.cover_calls drop constraint if exists cover_calls_early_note_len;
alter table public.cover_calls add constraint cover_calls_early_note_len check (early_note is null or length(early_note) <= 80);

create or replace function public.admin_decide_offer(offer_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.shift_offers; cw bigint; call public.cover_calls; sid bigint;
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into o from public.shift_offers where id = offer_id for update;
  if o.id is null or o.status <> 'offered' then raise exception 'That offer has already been dealt with.'; end if;
  if not yes then update public.shift_offers set status = 'declined', decided_at = now() where id = o.id; return; end if;
  select * into call from public.cover_calls where shift_date = o.shift_date and session = o.session and job = o.job and status = 'open' for update;
  perform set_config('app.cover', '1', true);
  insert into public.shifts (shift_date, session, job, staff_id, start_early, early_note)
  values (o.shift_date, o.session, o.job, o.staff_id, call.start_early, call.early_note) returning id into sid;
  perform set_config('app.cover', '', true);
  perform public.push_to(o.staff_id, '✅ You’ve got the shift', initcap(public.push_shift_txt((select max(id) from public.shifts where shift_date = o.shift_date and session = o.session and job = o.job and staff_id = o.staff_id))) || '. Thanks for covering!', '/?go=myshifts');
  select id into cw from public.shifts where shift_date = o.shift_date and session = o.session and job = o.job
     and status in ('cannot_work', 'sick', 'no_show') and not covered order by id limit 1;
  if cw is not null then update public.shifts set covered = true, decision = coalesce(decision, case when status = 'cannot_work' then 'approved' end), decided_at = now() where id = cw; end if;
  update public.shift_offers set status = 'accepted', decided_at = now() where id = o.id;
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

-- If the manager changes the start time after asking, everyone who said yes is told
create or replace function public.push_on_cover_time() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'open' and new.start_early is distinct from old.start_early then
    insert into public.push_queue (kind, audience, user_id, title, body, url)
    select 'shifts', 'user', o.staff_id, '⏰ Cover shift time changed',
      case new.job when 'door' then 'Door' when 'event' then 'Function Room Bar' else 'Lounge Bar' end || ' ' || trim(to_char(new.shift_date, 'Dy FMDD Mon'))
      || ': now starts ' || coalesce(to_char(new.start_early, 'HH24:MI'), 'at the normal time') || coalesce(' · ' || nullif(new.early_note, ''), '') || '. You can still say no.', '/?go=myshifts'
    from public.shift_offers o where o.shift_date = new.shift_date and o.session = new.session and o.job = new.job and o.status = 'offered';
  end if; return new;
end $$;
drop trigger if exists push_on_cover_time on public.cover_calls;
create trigger push_on_cover_time after update of start_early on public.cover_calls for each row execute function public.push_on_cover_time();
select 'Cover start times ready' as done;
