-- Staff can offer to work a shift that needs someone. The manager accepts (puts them on) or says no thanks.
create table if not exists public.shift_offers (
  id          bigint generated always as identity primary key,
  shift_date  date not null,
  session     text not null check (session in ('day', 'eve')),
  job         text not null check (job in ('lounge', 'event', 'door')),
  staff_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  status      text not null default 'offered' check (status in ('offered', 'accepted', 'declined', 'withdrawn')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
create unique index if not exists shift_offers_one_open on public.shift_offers (shift_date, session, job, staff_id) where status = 'offered';
create index if not exists shift_offers_date_idx on public.shift_offers (shift_date);
alter table public.shift_offers enable row level security;
drop policy if exists "staff see their own offers, admins all" on public.shift_offers;
create policy "staff see their own offers, admins all" on public.shift_offers
  for select to authenticated using (staff_id = auth.uid() or public.is_admin());

create or replace function public.staff_offer_shift(d date, sess text, j text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare sk text; new_id bigint;
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can do this.'; end if;
  if d < current_date then raise exception 'That shift has gone.'; end if;
  if not public.rota_published(d) then raise exception 'That rota isn''t published yet.'; end if;
  select skill into sk from public.profiles where id = auth.uid();
  if sk is null or not public.can_do_job(sk, j) then raise exception 'You''re not set up to work that job.'; end if;
  if exists (select 1 from public.shifts where staff_id = auth.uid() and shift_date = d and status in ('assigned', 'confirmed', 'late')) then
    raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.staff_unavailability where staff_id = auth.uid() and off_date = d) then
    raise exception 'You''ve marked yourself unavailable that day.'; end if;
  insert into public.shift_offers (shift_date, session, job, staff_id) values (d, sess, j, auth.uid()) returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'You''ve already offered for that shift.';
end $$;
grant execute on function public.staff_offer_shift(date, text, text) to authenticated;

create or replace function public.staff_withdraw_offer(offer_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shift_offers set status = 'withdrawn', decided_at = now() where id = offer_id and staff_id = auth.uid() and status = 'offered';
  if not found then raise exception 'The manager has already answered that offer.'; end if;
end $$;
grant execute on function public.staff_withdraw_offer(bigint) to authenticated;

create or replace function public.admin_decide_offer(offer_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.shift_offers; cw bigint;
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into o from public.shift_offers where id = offer_id for update;
  if o.id is null or o.status <> 'offered' then raise exception 'That offer has already been dealt with.'; end if;
  if not yes then update public.shift_offers set status = 'declined', decided_at = now() where id = o.id; return; end if;
  insert into public.shifts (shift_date, session, job, staff_id) values (o.shift_date, o.session, o.job, o.staff_id);
  -- If they're covering someone who can't work, that request is now approved
  select id into cw from public.shifts where shift_date = o.shift_date and session = o.session and job = o.job
     and status in ('cannot_work', 'sick', 'no_show') and not covered order by id limit 1;
  if cw is not null then update public.shifts set covered = true, decision = case when status = 'cannot_work' then 'approved' else decision end, decided_at = now() where id = cw; end if;
  update public.shift_offers set status = 'accepted', decided_at = now() where id = o.id;
end $$;
grant execute on function public.admin_decide_offer(bigint, boolean) to authenticated;
