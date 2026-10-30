-- =====================================================================
-- Staff messages to the manager, unplanned absence vs special circumstances,
-- and "ask everyone to cover" call-outs. Run after update-swap-board.sql.
-- =====================================================================

-- 1) Unplanned absence: on the record unless the manager marks special circumstances
alter table public.shifts add column if not exists excused boolean not null default false;

-- 2) Messages from staff to the manager
create table if not exists public.staff_messages (
  id          bigint generated always as identity primary key,
  staff_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  topic       text not null check (topic in ('cant_work', 'ill', 'club_problem', 'abuse', 'complaint', 'other')),
  body        text not null check (length(body) between 1 and 600),
  shift_id    bigint references public.shifts on delete set null,
  status      text not null default 'new' check (status in ('new', 'seen', 'done')),
  reply       text check (reply is null or length(reply) <= 600),
  created_at  timestamptz not null default now(),
  replied_at  timestamptz
);
create index if not exists staff_messages_staff_idx on public.staff_messages (staff_id, created_at desc);
alter table public.staff_messages enable row level security;
drop policy if exists "staff see their own messages, admins all" on public.staff_messages;
create policy "staff see their own messages, admins all" on public.staff_messages
  for select to authenticated using (staff_id = auth.uid() or public.is_admin());
drop policy if exists "staff send messages" on public.staff_messages;
create policy "staff send messages" on public.staff_messages
  for insert to authenticated with check (staff_id = auth.uid() and public.is_staff_or_admin() and status = 'new' and reply is null);
drop policy if exists "admins answer messages" on public.staff_messages;
create policy "admins answer messages" on public.staff_messages
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- 3) Cover call-outs: the manager asks everyone who could work a shift
create table if not exists public.cover_calls (
  id          bigint generated always as identity primary key,
  shift_date  date not null,
  session     text not null check (session in ('day', 'eve')),
  job         text not null check (job in ('lounge', 'event', 'door')),
  note        text,
  status      text not null default 'open' check (status in ('open', 'filled', 'cancelled')),
  created_at  timestamptz not null default now()
);
create unique index if not exists cover_calls_one_open on public.cover_calls (shift_date, session, job) where status = 'open';
alter table public.cover_calls enable row level security;
drop policy if exists "staff see cover calls" on public.cover_calls;
create policy "staff see cover calls" on public.cover_calls for select to authenticated using (public.is_staff_or_admin());
drop policy if exists "admins manage cover calls" on public.cover_calls;
create policy "admins manage cover calls" on public.cover_calls for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Staff can say "no" to a cover call (kept with their offers so the manager sees who answered)
alter table public.shift_offers drop constraint if exists shift_offers_status_check;
alter table public.shift_offers add constraint shift_offers_status_check check (status in ('offered', 'accepted', 'declined', 'withdrawn', 'passed'));

create or replace function public.staff_pass_cover(d date, sess text, j text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can do this.'; end if;
  if not exists (select 1 from public.shift_offers where shift_date = d and session = sess and job = j and staff_id = auth.uid() and status in ('offered', 'passed')) then
    insert into public.shift_offers (shift_date, session, job, staff_id, status) values (d, sess, j, auth.uid(), 'passed');
  end if;
end $$;
grant execute on function public.staff_pass_cover(date, text, text) to authenticated;

-- Accepting an offer also closes the cover call and turns away the other offers for that shift
create or replace function public.admin_decide_offer(offer_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.shift_offers; cw bigint;
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
  update public.shift_offers set status = 'declined', decided_at = now()
   where shift_date = o.shift_date and session = o.session and job = o.job and status = 'offered' and id <> o.id;
  update public.cover_calls set status = 'filled' where shift_date = o.shift_date and session = o.session and job = o.job and status = 'open';
end $$;
grant execute on function public.admin_decide_offer(bigint, boolean) to authenticated;
