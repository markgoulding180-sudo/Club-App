-- Cover: someone who is off that day (can't work, sick or no-show) is never asked to cover, and can't say yes.
-- Also: cleaning that morning doesn't stop someone being asked to cover a bar / door shift.
-- Run after update-clean-checks.sql. Safe to run again.

create or replace function public.push_on_cover_call() returns trigger language plpgsql security definer set search_path = '' as $$
declare txt text := case new.job when 'door' then 'Door' when 'event' then 'Function Room Bar' when 'clean' then 'Cleaning' else 'Lounge Bar' end || ' '
  || case when new.job = 'clean' then 'morning' when new.session = 'day' then 'daytime' else 'evening' end || ', ' || trim(to_char(new.shift_date, 'Dy FMDD Mon'));
begin
  if new.status = 'open' then
    insert into public.push_queue (kind, audience, user_id, title, body, url)
    select 'shifts', 'user', p.id, '📣 Cover needed: can you work?', txt || '. Tap Yes or No.', '/?go=myshifts'
    from public.profiles p
    where p.role in ('staff', 'admin') and p.skill is not null and public.can_do_job(p.skill, new.job)
      and not exists (select 1 from public.shifts x where x.staff_id = p.id and x.shift_date = new.shift_date
                        and ((x.status in ('assigned', 'confirmed', 'late') and (x.job = 'clean') = (new.job = 'clean'))
                             or x.status in ('cannot_work', 'sick', 'no_show')))
      and not exists (select 1 from public.staff_unavailability u where u.staff_id = p.id and u.off_date = new.shift_date);
  end if; return new;
end $$;
drop trigger if exists push_on_cover_call on public.cover_calls;
create trigger push_on_cover_call after insert on public.cover_calls for each row execute function public.push_on_cover_call();

create or replace function public.staff_offer_shift(d date, sess text, j text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare sk text; new_id bigint;
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can do this.'; end if;
  if d < current_date then raise exception 'That shift has gone.'; end if;
  if not public.rota_published(d) then raise exception 'That rota isn''t published yet.'; end if;
  select skill into sk from public.profiles where id = auth.uid();
  if sk is null or not public.can_do_job(sk, j) then raise exception 'You''re not set up to work that job.'; end if;
  if exists (select 1 from public.shifts where staff_id = auth.uid() and shift_date = d and status in ('cannot_work', 'sick', 'no_show')) then
    raise exception 'You''re off that day, so you can''t cover a shift on it.'; end if;
  if exists (select 1 from public.shifts where staff_id = auth.uid() and shift_date = d and status in ('assigned', 'confirmed', 'late') and (job = 'clean') = (j = 'clean')) then
    raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.staff_unavailability where staff_id = auth.uid() and off_date = d) then
    raise exception 'You''ve marked yourself unavailable that day.'; end if;
  insert into public.shift_offers (shift_date, session, job, staff_id) values (d, sess, j, auth.uid()) returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'You''ve already offered for that shift.';
end $$;
grant execute on function public.staff_offer_shift(date, text, text) to authenticated;

select 'Cover off-day check ready' as done;
