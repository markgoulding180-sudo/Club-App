-- =====================================================================
-- Ashford Railway Club app — Supabase schema (v10: tickets, holidays, member + club bookings, rota, staff records, payments, no-booking days)
-- Run once in the NEW project: Dashboard → SQL Editor → paste → Run.
-- =====================================================================

-- ---------- Profiles (one row per signed-up person) ----------
create table public.profiles (
  id             uuid primary key references auth.users on delete cascade,
  first_name     text,
  last_name      text,
  phone          text,
  email          text,
  membership_no  text,
  role           text not null default 'user' check (role in ('user', 'staff', 'admin')),
  skill          text check (skill in ('bar', 'door', 'both')),   -- which shifts they can work
  created_at     timestamptz not null default now()
);

-- Copy the sign-up form fields into profiles automatically
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, first_name, last_name, phone, membership_no, email)
  values (new.id, new.raw_user_meta_data->>'first_name', new.raw_user_meta_data->>'last_name',
          new.raw_user_meta_data->>'phone', new.raw_user_meta_data->>'membership_no', new.email);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;
create or replace function public.is_staff_or_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('staff', 'admin'));
$$;

alter table public.profiles enable row level security;
create policy "read own profile or admin reads all" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "update own profile" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
-- People may only change their own contact details — never their role or skill
revoke update on public.profiles from authenticated, anon;
grant update (first_name, last_name, phone, membership_no) on public.profiles to authenticated;

-- Admin: change someone's account type (customer / staff / admin) and what shifts they can work
create or replace function public.admin_set_profile(pid uuid, new_role text, new_skill text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can change accounts.'; end if;
  if pid = auth.uid() and new_role <> 'admin' then raise exception 'You can’t remove your own admin access.'; end if;
  update public.profiles set
    role  = new_role,
    skill = case when new_role = 'user' then null
                 when new_role = 'staff' then coalesce(new_skill, 'both')
                 else new_skill end
  where id = pid;
end $$;
grant execute on function public.admin_set_profile(uuid, text, text) to authenticated;

-- Staff list for the rota (names + what they can do), visible to staff and admins
create or replace function public.get_staff()
returns table (id uuid, first_name text, last_name text, skill text, role text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.first_name, p.last_name, p.skill, p.role
  from public.profiles p
  where public.is_staff_or_admin() and p.role in ('staff', 'admin') and p.skill is not null
  order by p.first_name, p.last_name;
$$;
grant execute on function public.get_staff() to authenticated;


-- ---------- What's On ----------
create table public.events (
  id           bigint generated always as identity primary key,
  title        text not null,
  description  text,
  category     text,
  starts_at    timestamptz not null,
  created_by   uuid default auth.uid() references auth.users on delete set null,
  created_at   timestamptz not null default now()
);
create index events_starts_at_idx on public.events (starts_at);

alter table public.events enable row level security;
create policy "anyone can read events" on public.events
  for select to anon, authenticated using (true);
create policy "admins manage events" on public.events
  for all to authenticated using (public.is_admin()) with check (public.is_admin());


-- ---------- Hall / Lounge bookings ----------
create table public.bookings (
  id              bigint generated always as identity primary key,
  room            text not null check (room in ('hall', 'lounge')),
  booking_date    date not null,
  slot            text not null check (slot in ('afternoon', 'evening', 'full_day')),
  status          text not null default 'pending' check (status in ('pending', 'confirmed', 'cancelled')),
  user_id         uuid default auth.uid() references auth.users on delete set null,
  first_name      text not null,
  last_name       text not null,
  customer_phone  text,
  customer_email  text,
  membership_no   text,
  event_type      text not null default 'Other',
  event_details   jsonb not null default '{}'::jsonb,   -- extra answers, e.g. 18th birthday: celebrant, id_checks, door_notes
  guests          int check (guests is null or guests > 0),
  notes           text,
  price           numeric(8,2),
  deposit_required numeric(8,2) not null default 100,  -- secures the booking; never more than the hire price in the app
  booking_kind    text not null default 'member' check (booking_kind in ('member', 'club')),  -- club = the club's own event
  start_time      time,                                  -- club events: exact times
  end_time        time,
  ticketed        boolean not null default false,        -- club events: ticket or free
  price_member    numeric(8,2),
  price_guest     numeric(8,2),
  bar_staff       int check (bar_staff is null or bar_staff between 0 and 10),  -- club events: people on that room's bar (1 or 2)
  created_at      timestamptz not null default now()
);
create index bookings_date_room_idx on public.bookings (booking_date, room);
create index bookings_user_idx on public.bookings (user_id);

-- "No bookings" days: all day, or just the afternoon or evening. Members can't book; admins still can.
create table public.closed_days (
  id           bigint generated always as identity primary key,
  closed_date  date not null,
  part         text not null default 'all' check (part in ('all', 'afternoon', 'evening')),
  reason       text,                                  -- only admins see this
  created_by   uuid default auth.uid() references auth.users on delete set null,
  created_at   timestamptz not null default now(),
  unique (closed_date, part)
);
alter table public.closed_days enable row level security;
create policy "admins manage closed days" on public.closed_days
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Everyone can see which days are closed; only admins get the reason
create or replace function public.get_closed_days(from_date date, to_date date)
returns table (id bigint, closed_date date, part text, reason text)
language sql stable security definer set search_path = '' as $$
  select c.id, c.closed_date, c.part, case when public.is_admin() then c.reason end
  from public.closed_days c where c.closed_date between from_date and to_date;
$$;
grant execute on function public.get_closed_days(date, date) to anon, authenticated;

-- Stop double bookings (a full day blocks both sessions), and stop members booking a no-bookings day
create or replace function public.check_booking_clash()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'cancelled' and not public.is_admin()
     and exists (select 1 from public.closed_days c
                 where c.closed_date = new.booking_date
                   and (c.part = 'all' or new.slot = 'full_day' or c.part = new.slot)) then
    raise exception 'Sorry, the club isn''t taking bookings for that day.';
  end if;
  if new.status <> 'cancelled' and exists (
    select 1 from public.bookings b
    where b.room = new.room and b.booking_date = new.booking_date and b.status <> 'cancelled'
      and b.id is distinct from new.id
      and (b.slot = new.slot or b.slot = 'full_day' or new.slot = 'full_day')
  ) then
    raise exception 'That room is already booked for this session.';
  end if;
  return new;
end $$;

create trigger bookings_no_clash
  before insert or update on public.bookings
  for each row execute function public.check_booking_clash();

alter table public.bookings enable row level security;
create policy "see own bookings, admin sees all" on public.bookings
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "customers request, admins add" on public.bookings
  for insert to authenticated
  with check (public.is_admin() or (user_id = auth.uid() and status = 'pending' and booking_kind = 'member'));
create policy "everyone signed in sees club events" on public.bookings
  for select to authenticated using (booking_kind = 'club' and status <> 'cancelled');
create policy "admins update bookings" on public.bookings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins delete bookings" on public.bookings
  for delete to authenticated using (public.is_admin());

-- Public availability: which sessions are taken, without anyone's details
create or replace function public.get_availability(from_date date, to_date date)
returns table (booking_date date, room text, slot text, status text)
language sql stable security definer set search_path = '' as $$
  select b.booking_date, b.room, b.slot, b.status
  from public.bookings b
  where b.status <> 'cancelled' and b.booking_date between from_date and to_date;
$$;
grant execute on function public.get_availability(date, date) to anon, authenticated;

-- What staff see on the rota: the event, room, session and guests — no contact details
create or replace function public.get_day_summaries(from_date date, to_date date)
returns table (booking_date date, room text, slot text, event_type text, guests int, status text, booking_name text,
               booking_kind text, start_time time, end_time time, bar_staff int)
language sql stable security definer set search_path = '' as $$
  select b.booking_date, b.room, b.slot, b.event_type, b.guests, b.status, trim(coalesce(b.first_name,'') || ' ' || coalesce(b.last_name,'')),
         b.booking_kind, b.start_time, b.end_time, b.bar_staff
  from public.bookings b
  where public.is_staff_or_admin() and b.status <> 'cancelled' and b.booking_date between from_date and to_date;
$$;
grant execute on function public.get_day_summaries(date, date) to authenticated;

-- Let a customer cancel their own upcoming booking
create or replace function public.cancel_my_booking(booking_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.bookings set status = 'cancelled'
  where id = booking_id and user_id = auth.uid()
    and status in ('pending', 'confirmed') and booking_date >= current_date;
  if not found then raise exception 'Booking not found or can no longer be cancelled.'; end if;
end $$;
revoke execute on function public.cancel_my_booking(bigint) from anon;
grant execute on function public.cancel_my_booking(bigint) to authenticated;


-- ---------- Payments (each one tied to a booking and, if linked, the member's account) ----------
create table public.payments (
  id          bigint generated always as identity primary key,
  booking_id  bigint not null references public.bookings on delete cascade,
  user_id     uuid references auth.users on delete set null,
  amount      numeric(8,2) not null check (amount > 0),
  kind        text not null default 'deposit' check (kind in ('deposit', 'balance', 'refund')),
  method      text not null default 'cash' check (method in ('cash', 'card', 'bank', 'other')),
  paid_on     date not null default current_date,
  note        text,
  taken_by    uuid default auth.uid() references auth.users on delete set null,
  created_at  timestamptz not null default now()
);
create index payments_booking_idx on public.payments (booking_id);
create index payments_paid_on_idx on public.payments (paid_on);

-- Keep the payment's member in step with the booking
create or replace function public.payment_user_from_booking()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  select b.user_id into new.user_id from public.bookings b where b.id = new.booking_id;
  return new;
end $$;
create trigger payments_set_user before insert on public.payments
  for each row execute function public.payment_user_from_booking();

alter table public.payments enable row level security;
create policy "admins manage payments" on public.payments
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "members see payments on their bookings" on public.payments
  for select to authenticated using (exists (select 1 from public.bookings b where b.id = booking_id and b.user_id = auth.uid()));


-- ---------- Staff rota ----------
-- One row per person per shift. session: 'day' or 'eve' (opening times live in the app).
-- job: 'lounge' (Lounge Bar), 'event' (extra bar for a booking), 'door'.
create table public.shifts (
  id          bigint generated always as identity primary key,
  shift_date  date not null,
  session     text not null check (session in ('day', 'eve')),
  job         text not null check (job in ('lounge', 'event', 'door')),
  staff_id    uuid not null references public.profiles on delete cascade,
  status      text not null default 'assigned'
              check (status in ('assigned', 'confirmed', 'cannot_work', 'late', 'sick', 'no_show')),
  reason      text,                                  -- why they can't work / were off
  covered     boolean not null default false,        -- true once someone else has been put on
  created_at  timestamptz not null default now()
);
create index shifts_date_idx on public.shifts (shift_date);
create index shifts_staff_idx on public.shifts (staff_id, shift_date);
-- A person can only be on one job per shift
create unique index shifts_one_per_session on public.shifts (shift_date, session, staff_id)
  where status in ('assigned', 'confirmed', 'late');

alter table public.shifts enable row level security;
create policy "staff and admins see the rota" on public.shifts
  for select to authenticated using (public.is_staff_or_admin());
create policy "admins manage the rota" on public.shifts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Days a staff member can't work (whether or not they're rostered)
create table public.staff_unavailability (
  id         bigint generated always as identity primary key,
  staff_id   uuid not null default auth.uid() references public.profiles on delete cascade,
  off_date   date not null,
  reason     text,
  created_at timestamptz not null default now(),
  unique (staff_id, off_date)
);
alter table public.staff_unavailability enable row level security;
create policy "staff and admins see days off" on public.staff_unavailability
  for select to authenticated using (public.is_staff_or_admin());
create policy "staff remove their own days, admins any" on public.staff_unavailability
  for delete to authenticated using (staff_id = auth.uid() or public.is_admin());

-- Admin-only record of each staff member (sick, didn't turn up, late, notes)
create table public.staff_notes (
  id         bigint generated always as identity primary key,
  staff_id   uuid not null references public.profiles on delete cascade,
  note_date  date not null default current_date,
  kind       text not null check (kind in ('sick', 'no_show', 'late', 'cannot_work', 'note')),
  note       text,
  created_by uuid default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now()
);
create index staff_notes_staff_idx on public.staff_notes (staff_id, note_date);
alter table public.staff_notes enable row level security;
create policy "admins only" on public.staff_notes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Staff: say they can't make a shift (shows on the admin's Rota). Shifts don't need confirming.
create or replace function public.staff_update_shift(shift_id bigint, new_status text, why text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if new_status <> 'cannot_work' then raise exception 'Staff can only say they can''t make a shift.'; end if;
  update public.shifts set status = new_status, reason = case when new_status = 'cannot_work' then why else reason end
  where id = shift_id and staff_id = auth.uid() and shift_date >= current_date and status in ('assigned', 'confirmed');
  if not found then raise exception 'Shift not found or already changed.'; end if;
end $$;
grant execute on function public.staff_update_shift(bigint, text, text) to authenticated;

-- Staff: add a day they can't work. Any shifts they already have that day are flagged for cover.
create or replace function public.staff_mark_unavailable(d date, why text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can do this.'; end if;
  if d < current_date then raise exception 'Pick today or a later date.'; end if;
  insert into public.staff_unavailability (staff_id, off_date, reason) values (auth.uid(), d, why);
  update public.shifts set status = 'cannot_work', reason = coalesce(why, 'Marked as can''t work')
  where staff_id = auth.uid() and shift_date = d and status in ('assigned', 'confirmed');
exception when unique_violation then
  raise exception 'You have already marked that day.';
end $$;
grant execute on function public.staff_mark_unavailable(date, text) to authenticated;

-- Staff: undo a day off. They go back on any shift that day that hasn't been covered yet.
create or replace function public.staff_remove_unavailable(off_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare d date; who uuid;
begin
  delete from public.staff_unavailability where id = off_id and (staff_id = auth.uid() or public.is_admin())
  returning off_date, staff_id into d, who;
  if d is null then raise exception 'Day not found.'; end if;
  update public.shifts s set status = 'assigned', reason = null
  where s.staff_id = who and s.shift_date = d and s.status = 'cannot_work' and not s.covered
    and not exists (select 1 from public.shifts o where o.staff_id = who and o.shift_date = d and o.session = s.session and o.id <> s.id and o.status in ('assigned','confirmed','late'));
end $$;
grant execute on function public.staff_remove_unavailable(bigint) to authenticated;


-- ---------- Holidays ----------
-- Holiday requests: staff ask, admin approves. 28 days a year (Jan–Dec).
create table if not exists public.holiday_requests (
  id          bigint generated always as identity primary key,
  staff_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  days        date[] not null check (cardinality(days) between 1 and 28),
  note        text,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  admin_note  text,
  decided_by  uuid references auth.users on delete set null,
  decided_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists holiday_requests_staff_idx on public.holiday_requests (staff_id);
alter table public.holiday_requests enable row level security;
drop policy if exists "staff see their own holidays, admins all" on public.holiday_requests;
create policy "staff see their own holidays, admins all" on public.holiday_requests
  for select to authenticated using (staff_id = auth.uid() or public.is_admin());
-- (all changes go through the functions below)

-- Approved holiday days show as days off on the rota
alter table public.staff_unavailability add column if not exists holiday_id bigint references public.holiday_requests on delete cascade;

-- Days used (approved) + waiting (pending) in a year
create or replace function public.holiday_days_taken(who uuid, yr int)
returns int language sql stable security definer set search_path = '' as $$
  select coalesce(sum((select count(*) from unnest(h.days) d where extract(year from d) = yr)), 0)::int
  from public.holiday_requests h where h.staff_id = who and h.status in ('pending', 'approved');
$$;

-- Staff: ask for holiday
create or replace function public.staff_request_holiday(want date[], why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare picked date[]; yr int; n int; clash date; new_id bigint;
begin
  if not public.is_staff_or_admin() then raise exception 'Only staff can book holiday.'; end if;
  picked := array(select distinct d from unnest(want) d where d is not null order by d);
  if cardinality(picked) = 0 then raise exception 'Pick at least one day.'; end if;
  if picked[1] < current_date then raise exception 'Pick today or later.'; end if;
  select d into clash from public.holiday_requests h, unnest(h.days) d
   where h.staff_id = auth.uid() and h.status in ('pending', 'approved') and d = any(picked) limit 1;
  if clash is not null then raise exception 'You already have holiday booked or asked for on %.', to_char(clash, 'Dy DD Mon'); end if;
  for yr, n in select extract(year from d)::int, count(*) from unnest(picked) d group by 1 loop
    if public.holiday_days_taken(auth.uid(), yr) + n > 28 then
      raise exception 'That would go over your 28 days for %. You have % left.', yr, greatest(0, 28 - public.holiday_days_taken(auth.uid(), yr));
    end if;
  end loop;
  insert into public.holiday_requests (staff_id, days, note) values (auth.uid(), picked, nullif(trim(why), '')) returning id into new_id;
  return new_id;
end $$;
grant execute on function public.staff_request_holiday(date[], text) to authenticated;

-- Staff: withdraw a request that hasn't been decided yet
create or replace function public.staff_cancel_holiday(req bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.holiday_requests set status = 'cancelled' where id = req and staff_id = auth.uid() and status = 'pending';
  if not found then raise exception 'Request not found, or the manager has already answered it.'; end if;
end $$;
grant execute on function public.staff_cancel_holiday(bigint) to authenticated;

-- Admin: approve / decline a request, or cancel an approved holiday
create or replace function public.admin_decide_holiday(req bigint, new_status text, why text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.holiday_requests;
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into r from public.holiday_requests where id = req for update;
  if r.id is null then raise exception 'Request not found.'; end if;
  if new_status in ('approved', 'declined') and r.status <> 'pending' then raise exception 'That request has already been answered.'; end if;
  if new_status = 'cancelled' and r.status <> 'approved' then raise exception 'Only approved holidays can be cancelled here.'; end if;
  if new_status not in ('approved', 'declined', 'cancelled') then raise exception 'Unknown choice.'; end if;

  update public.holiday_requests set status = new_status, admin_note = nullif(trim(why), ''), decided_by = auth.uid(), decided_at = now() where id = req;

  if new_status = 'approved' then
    insert into public.staff_unavailability (staff_id, off_date, reason, holiday_id)
      select r.staff_id, d, 'Holiday', r.id from unnest(r.days) d
    on conflict (staff_id, off_date) do nothing;   -- already marked off: keep their own entry
    update public.shifts set status = 'cannot_work', reason = 'Holiday'
     where staff_id = r.staff_id and shift_date = any(r.days) and status in ('assigned', 'confirmed');
  elsif new_status = 'cancelled' then
    delete from public.staff_unavailability where holiday_id = r.id;
    update public.shifts s set status = 'assigned', reason = null
     where s.staff_id = r.staff_id and s.shift_date = any(r.days) and s.shift_date >= current_date
       and s.status = 'cannot_work' and s.reason = 'Holiday' and not s.covered
       and not exists (select 1 from public.shifts o where o.staff_id = s.staff_id and o.shift_date = s.shift_date and o.session = s.session and o.id <> s.id and o.status in ('assigned','confirmed','late'));
  end if;
end $$;
grant execute on function public.admin_decide_holiday(bigint, text, text) to authenticated;

-- Staff can't untick a booked holiday day themselves (the manager cancels it instead)
create or replace function public.staff_remove_unavailable(off_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare d date; who uuid;
begin
  if exists (select 1 from public.staff_unavailability where id = off_id and holiday_id is not null) and not public.is_admin() then
    raise exception 'That day is booked holiday. Ask the manager if you want to change it.';
  end if;
  delete from public.staff_unavailability where id = off_id and (staff_id = auth.uid() or public.is_admin())
  returning off_date, staff_id into d, who;
  if d is null then raise exception 'Day not found.'; end if;
  update public.shifts s set status = 'assigned', reason = null
  where s.staff_id = who and s.shift_date = d and s.status = 'cannot_work' and not s.covered
    and not exists (select 1 from public.shifts o where o.staff_id = who and o.shift_date = d and o.session = s.session and o.id <> s.id and o.status in ('assigned','confirmed','late'));
end $$;
grant execute on function public.staff_remove_unavailable(bigint) to authenticated;

-- ---------- Tickets ----------
-- Tickets: members pre-book tickets for ticketed club events. Payment is recorded by the admin for now.
alter table public.bookings add column if not exists tickets_total int check (tickets_total is null or tickets_total > 0);  -- blank = no limit
alter table public.bookings add column if not exists banner_url text;                                                      -- optional picture for the event

create table if not exists public.ticket_reservations (
  id            bigint generated always as identity primary key,
  booking_id    bigint not null references public.bookings on delete cascade,
  user_id       uuid default auth.uid() references auth.users on delete set null,
  first_name    text,
  last_name     text,
  email         text,
  phone         text,
  membership_no text,
  member_qty    int not null default 0 check (member_qty between 0 and 50),
  guest_qty     int not null default 0 check (guest_qty between 0 and 50),
  price_member  numeric(8,2) not null default 0,
  price_guest   numeric(8,2) not null default 0,
  total         numeric(8,2) not null default 0,
  status        text not null default 'reserved' check (status in ('reserved', 'paid', 'cancelled')),
  note          text,
  paid_at       timestamptz,
  created_at    timestamptz not null default now(),
  check (member_qty + guest_qty > 0)
);
create index if not exists ticket_reservations_booking_idx on public.ticket_reservations (booking_id);
create index if not exists ticket_reservations_user_idx on public.ticket_reservations (user_id);

alter table public.ticket_reservations enable row level security;
drop policy if exists "members see their own tickets, admins all" on public.ticket_reservations;
create policy "members see their own tickets, admins all" on public.ticket_reservations
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "admins manage tickets" on public.ticket_reservations;
create policy "admins manage tickets" on public.ticket_reservations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- How many tickets are taken for each event (no names)
create or replace function public.get_ticket_counts(ids bigint[])
returns table (booking_id bigint, sold int)
language sql stable security definer set search_path = '' as $$
  select t.booking_id, coalesce(sum(t.member_qty + t.guest_qty), 0)::int
  from public.ticket_reservations t
  where t.booking_id = any(ids) and t.status <> 'cancelled'
  group by t.booking_id;
$$;
grant execute on function public.get_ticket_counts(bigint[]) to authenticated;

-- Member: reserve (or change) their tickets for an event
create or replace function public.reserve_tickets(event_id bigint, members int, guests int, why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare ev public.bookings; me public.profiles; mine public.ticket_reservations; taken int; new_id bigint;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  select * into ev from public.bookings where id = event_id for update;
  if ev.id is null or ev.booking_kind <> 'club' or not ev.ticketed or ev.status = 'cancelled' then raise exception 'Tickets aren''t available for this event.'; end if;
  if ev.booking_date < current_date then raise exception 'This event has already happened.'; end if;
  members := coalesce(members, 0); guests := coalesce(guests, 0);
  if members < 0 or guests < 0 or members + guests < 1 then raise exception 'Pick at least one ticket.'; end if;
  if members + guests > 20 then raise exception 'You can reserve up to 20 tickets. Call the club for more.'; end if;

  select * into mine from public.ticket_reservations
   where booking_id = event_id and user_id = auth.uid() and status = 'reserved' order by id desc limit 1;
  select coalesce(sum(member_qty + guest_qty), 0) into taken from public.ticket_reservations
   where booking_id = event_id and status <> 'cancelled' and id is distinct from mine.id;
  if ev.tickets_total is not null and taken + members + guests > ev.tickets_total then
    raise exception 'Sorry, only % tickets left.', greatest(0, ev.tickets_total - taken);
  end if;

  select * into me from public.profiles where id = auth.uid();
  if mine.id is not null then
    update public.ticket_reservations set member_qty = members, guest_qty = guests,
      price_member = coalesce(ev.price_member, 0), price_guest = coalesce(ev.price_guest, 0),
      total = members * coalesce(ev.price_member, 0) + guests * coalesce(ev.price_guest, 0),
      note = nullif(trim(why), '')
    where id = mine.id;
    return mine.id;
  end if;
  insert into public.ticket_reservations (booking_id, user_id, first_name, last_name, email, phone, membership_no,
    member_qty, guest_qty, price_member, price_guest, total, note)
  values (event_id, auth.uid(), me.first_name, me.last_name, me.email, me.phone, me.membership_no,
    members, guests, coalesce(ev.price_member, 0), coalesce(ev.price_guest, 0),
    members * coalesce(ev.price_member, 0) + guests * coalesce(ev.price_guest, 0), nullif(trim(why), ''))
  returning id into new_id;
  return new_id;
end $$;
grant execute on function public.reserve_tickets(bigint, int, int, text) to authenticated;

-- Member: cancel their reservation before the event (not once it's paid)
create or replace function public.cancel_my_tickets(res bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.ticket_reservations t set status = 'cancelled'
  where t.id = res and t.user_id = auth.uid() and t.status = 'reserved'
    and exists (select 1 from public.bookings b where b.id = t.booking_id and b.booking_date >= current_date);
  if not found then raise exception 'Those tickets can''t be cancelled. Please speak to the club.'; end if;
end $$;
grant execute on function public.cancel_my_tickets(bigint) to authenticated;

-- ---------- Sign-in page What's On ----------
-- Sign-in page: the next few What's On items (What's On list + club events), no personal details
create or replace function public.get_public_whats_on(max_rows int default 3)
returns table (title text, starts_at timestamptz, info text, kind text)
language sql stable security definer set search_path = '' as $$
  select x.title, x.starts_at, x.info, x.kind from (
    select e.title, e.starts_at, coalesce(e.category, '') as info, 'event'::text as kind
    from public.events e
    where e.starts_at >= date_trunc('day', now())
    union all
    select b.event_type,
           (b.booking_date + coalesce(b.start_time, time '19:00')) at time zone 'Europe/London',
           (case b.room when 'hall' then 'Function Room' else 'Lounge Bar' end) || (case when b.ticketed then ' · Tickets' else ' · Free entry' end),
           'club'
    from public.bookings b
    where b.booking_kind = 'club' and b.status <> 'cancelled' and b.booking_date >= current_date
  ) x
  order by x.starts_at
  limit least(greatest(coalesce(max_rows, 3), 1), 10);
$$;
grant execute on function public.get_public_whats_on(int) to anon, authenticated;

-- =====================================================================
-- AFTER you have signed up in the app with your own email, make yourself
-- admin by running this (change the email):
--
--   update public.profiles set role = 'admin' where email = 'you@example.com';
--
-- Staff then register in the app and you switch them to Staff on the
-- "Staff team" screen.
-- =====================================================================
-- Regular shifts: the days each staff member normally works, e.g. [{"d":5,"s":"eve","j":"lounge"}]
-- d = day of week (0 Sun … 6 Sat), s = day/eve, j = lounge/event/door. Only admins can change it.
alter table public.profiles add column if not exists regular_shifts jsonb not null default '[]'::jsonb;

create or replace function public.admin_set_regular(pid uuid, pattern jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can set regular shifts.'; end if;
  if jsonb_typeof(pattern) <> 'array' or jsonb_array_length(pattern) > 14 then raise exception 'That pattern isn''t valid.'; end if;
  if exists (select 1 from jsonb_array_elements(pattern) x
             where (x->>'d') !~ '^[0-6]$' or x->>'s' not in ('day', 'eve') or x->>'j' not in ('lounge', 'event', 'door')) then
    raise exception 'That pattern isn''t valid.';
  end if;
  update public.profiles set regular_shifts = pattern where id = pid;
end $$;
grant execute on function public.admin_set_regular(uuid, jsonb) to authenticated;
-- Staff can only be on one shift a day (daytime OR evening, not both)
create or replace function public.shifts_one_a_day()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status in ('assigned', 'confirmed', 'late') and exists (
    select 1 from public.shifts o
    where o.staff_id = new.staff_id and o.shift_date = new.shift_date and o.id <> new.id
      and o.status in ('assigned', 'confirmed', 'late')) then
    raise exception 'They are already working that day.';
  end if;
  return new;
end $$;
drop trigger if exists shifts_one_a_day on public.shifts;
create trigger shifts_one_a_day before insert or update of staff_id, shift_date, status on public.shifts
  for each row execute function public.shifts_one_a_day();
-- Can't work requests: staff must give a reason; the manager approves (by putting cover on) or declines
alter table public.shifts add column if not exists decision text check (decision in ('approved', 'declined'));
alter table public.shifts add column if not exists decided_at timestamptz;

create or replace function public.staff_update_shift(shift_id bigint, new_status text, why text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if new_status <> 'cannot_work' then raise exception 'Staff can only say they can''t make a shift.'; end if;
  if length(trim(coalesce(why, ''))) < 3 then raise exception 'Please give a reason.'; end if;
  update public.shifts set status = 'cannot_work', reason = trim(why), decision = null, decided_at = null
  where id = shift_id and staff_id = auth.uid() and shift_date >= current_date and status in ('assigned', 'confirmed');
  if not found then raise exception 'Shift not found or already changed.'; end if;
end $$;
grant execute on function public.staff_update_shift(bigint, text, text) to authenticated;
-- =====================================================================
-- 4-weekly rotas: draft → publish, can't-work rules, withdraw, swaps,
-- and staff who leave come off their future shifts.
-- =====================================================================

-- ---------- Rota periods ----------
-- Rotas run 4 weeks from a Monday. The first one starts Mon 2 Nov 2026; every 28 days after that is the next.
create or replace function public.rota_anchor() returns date language sql immutable as $$ select date '2026-11-02' $$;
create or replace function public.rota_period_start(d date) returns date language sql immutable as $$
  select public.rota_anchor() + (floor((d - public.rota_anchor())::numeric / 28) * 28)::int
$$;

create table if not exists public.rota_periods (
  start_date   date primary key,
  published_at timestamptz,
  published_by uuid references auth.users on delete set null
);
alter table public.rota_periods enable row level security;
drop policy if exists "staff and admins see rota periods" on public.rota_periods;
create policy "staff and admins see rota periods" on public.rota_periods
  for select to authenticated using (public.is_staff_or_admin());

-- Is the rota for this day published? (Days before the first 4-week rota count as published.)
create or replace function public.rota_published(d date) returns boolean
language sql stable security definer set search_path = '' as $$
  select d < public.rota_anchor() or exists (
    select 1 from public.rota_periods p where p.start_date = public.rota_period_start(d) and p.published_at is not null)
$$;
grant execute on function public.rota_published(date) to authenticated;

-- Admin: publish (or take back) a rota
create or replace function public.admin_publish_rota(period_start date, publish boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can publish the rota.'; end if;
  if period_start <> public.rota_period_start(period_start) then raise exception 'That isn''t the start of a rota.'; end if;
  insert into public.rota_periods (start_date, published_at, published_by)
  values (period_start, case when publish then now() end, case when publish then auth.uid() end)
  on conflict (start_date) do update set published_at = excluded.published_at, published_by = excluded.published_by;
end $$;
grant execute on function public.admin_publish_rota(date, boolean) to authenticated;

-- Staff only see shifts once that rota is published. Admins see everything.
drop policy if exists "staff and admins see the rota" on public.shifts;
create policy "staff and admins see the rota" on public.shifts
  for select to authenticated using (public.is_admin() or (public.is_staff_or_admin() and public.rota_published(shift_date)));

-- ---------- Can't work: reason, 2 days' notice, 2 per rota, can withdraw ----------
create or replace function public.staff_update_shift(shift_id bigint, new_status text, why text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare sh public.shifts; used int;
begin
  if new_status <> 'cannot_work' then raise exception 'Staff can only say they can''t make a shift.'; end if;
  if length(trim(coalesce(why, ''))) < 3 then raise exception 'Please give a reason.'; end if;
  select * into sh from public.shifts where id = shift_id and staff_id = auth.uid() for update;
  if sh.id is null or sh.status not in ('assigned', 'confirmed') or not public.rota_published(sh.shift_date) then raise exception 'Shift not found or already changed.'; end if;
  if sh.shift_date < current_date + 2 then raise exception 'That shift is less than 2 days away. Please phone the manager.'; end if;
  select count(*) into used from public.shifts
   where staff_id = auth.uid() and id <> sh.id and public.rota_period_start(shift_date) = public.rota_period_start(sh.shift_date)
     and (status = 'cannot_work' or decision is not null);
  if used >= 2 then raise exception 'You''ve already asked off 2 shifts on this rota. Please speak to the manager.'; end if;
  update public.shifts set status = 'cannot_work', reason = trim(why), decision = null, decided_at = null where id = sh.id;
  update public.shift_swaps set status = 'cancelled', decided_at = now()
   where status in ('asked', 'accepted') and (from_shift = sh.id or to_shift = sh.id);
end $$;
grant execute on function public.staff_update_shift(bigint, text, text) to authenticated;

create or replace function public.staff_withdraw_cantwork(shift_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shifts set status = 'assigned', reason = null
  where id = shift_id and staff_id = auth.uid() and status = 'cannot_work' and not covered and decision is null;
  if not found then raise exception 'The manager has already dealt with this one.'; end if;
end $$;
grant execute on function public.staff_withdraw_cantwork(bigint) to authenticated;

-- ---------- Staff who leave come off their future shifts ----------
create or replace function public.admin_set_profile(pid uuid, new_role text, new_skill text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can change accounts.'; end if;
  if pid = auth.uid() and new_role <> 'admin' then raise exception 'You can’t remove your own admin access.'; end if;
  update public.profiles set
    role  = new_role,
    skill = case when new_role = 'user' then null
                 when new_role = 'staff' then coalesce(new_skill, 'both')
                 else new_skill end
  where id = pid;
  if new_role = 'user' or (new_role = 'admin' and new_skill is null) then
    delete from public.shifts where staff_id = pid and shift_date >= current_date;   -- their shifts show as needing someone
    update public.profiles set regular_shifts = '[]'::jsonb where id = pid;
  end if;
end $$;

-- ---------- Shift swaps ----------
create table if not exists public.shift_swaps (
  id          bigint generated always as identity primary key,
  from_shift  bigint not null references public.shifts on delete cascade,
  to_shift    bigint not null references public.shifts on delete cascade,
  from_staff  uuid not null references public.profiles on delete cascade,
  to_staff    uuid not null references public.profiles on delete cascade,
  note        text,
  status      text not null default 'asked' check (status in ('asked', 'accepted', 'declined', 'approved', 'refused', 'cancelled')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
create index if not exists shift_swaps_from_idx on public.shift_swaps (from_staff);
create index if not exists shift_swaps_to_idx on public.shift_swaps (to_staff);
alter table public.shift_swaps enable row level security;
drop policy if exists "people in the swap and admins see it" on public.shift_swaps;
create policy "people in the swap and admins see it" on public.shift_swaps
  for select to authenticated using (from_staff = auth.uid() or to_staff = auth.uid() or public.is_admin());
-- (all changes go through the functions below)

create or replace function public.can_do_job(skill text, job text) returns boolean language sql immutable as $$
  select skill = 'both' or (job = 'door' and skill = 'door') or (job <> 'door' and skill = 'bar')
$$;

-- One shift a day, except while the manager approves a swap
create or replace function public.shifts_one_a_day()
returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('app.swapping', true), '') = '1' then return new; end if;
  if new.status in ('assigned', 'confirmed', 'late') and exists (
    select 1 from public.shifts o
    where o.staff_id = new.staff_id and o.shift_date = new.shift_date and o.id <> new.id
      and o.status in ('assigned', 'confirmed', 'late')) then
    raise exception 'They are already working that day.';
  end if;
  return new;
end $$;
drop trigger if exists shifts_one_a_day on public.shifts;
create trigger shifts_one_a_day before insert or update of staff_id, shift_date, status on public.shifts
  for each row execute function public.shifts_one_a_day();

-- Staff: ask a colleague to swap
create or replace function public.staff_ask_swap(mine bigint, theirs bigint, why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare a public.shifts; b public.shifts; sa text; sb text; new_id bigint;
begin
  select * into a from public.shifts where id = mine;
  select * into b from public.shifts where id = theirs;
  if a.id is null or a.staff_id <> auth.uid() or a.status not in ('assigned', 'confirmed') then raise exception 'That isn''t one of your shifts.'; end if;
  if b.id is null or b.staff_id = auth.uid() or b.status not in ('assigned', 'confirmed') then raise exception 'That shift can''t be swapped.'; end if;
  if a.shift_date <= current_date or b.shift_date <= current_date then raise exception 'Swaps need to be for tomorrow or later.'; end if;
  if not public.rota_published(a.shift_date) or not public.rota_published(b.shift_date) then raise exception 'That rota isn''t published yet.'; end if;
  if a.shift_date = b.shift_date then raise exception 'Pick a shift on a different day.'; end if;
  if exists (select 1 from public.shifts where staff_id = a.staff_id and shift_date = b.shift_date and status in ('assigned', 'confirmed', 'late')) then
    raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.shifts where staff_id = b.staff_id and shift_date = a.shift_date and status in ('assigned', 'confirmed', 'late')) then
    raise exception 'They''re already working on your day.'; end if;
  select skill into sa from public.profiles where id = a.staff_id;
  select skill into sb from public.profiles where id = b.staff_id;
  if not public.can_do_job(sa, b.job) or not public.can_do_job(sb, a.job) then raise exception 'You can''t both do each other''s jobs.'; end if;
  if exists (select 1 from public.shift_swaps where status in ('asked', 'accepted') and (from_shift in (a.id, b.id) or to_shift in (a.id, b.id))) then
    raise exception 'One of those shifts already has a swap waiting.'; end if;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note)
  values (a.id, b.id, a.staff_id, b.staff_id, nullif(trim(why), '')) returning id into new_id;
  return new_id;
end $$;
grant execute on function public.staff_ask_swap(bigint, bigint, text) to authenticated;

-- Staff: answer a swap someone asked you for
create or replace function public.staff_answer_swap(swap_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shift_swaps set status = case when yes then 'accepted' else 'declined' end, decided_at = case when yes then null else now() end
  where id = swap_id and to_staff = auth.uid() and status = 'asked';
  if not found then raise exception 'That swap has already been dealt with.'; end if;
end $$;
grant execute on function public.staff_answer_swap(bigint, boolean) to authenticated;

-- Staff: cancel a swap you asked for (before the manager approves)
create or replace function public.staff_cancel_swap(swap_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.shift_swaps set status = 'cancelled', decided_at = now()
  where id = swap_id and from_staff = auth.uid() and status in ('asked', 'accepted');
  if not found then raise exception 'That swap has already been dealt with.'; end if;
end $$;
grant execute on function public.staff_cancel_swap(bigint) to authenticated;

-- Admin: approve (swap the two shifts over) or refuse
create or replace function public.admin_decide_swap(swap_id bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare sw public.shift_swaps; a public.shifts; b public.shifts;
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  select * into sw from public.shift_swaps where id = swap_id for update;
  if sw.id is null or sw.status <> 'accepted' then raise exception 'That swap isn''t waiting for you.'; end if;
  if not yes then update public.shift_swaps set status = 'refused', decided_at = now() where id = sw.id; return; end if;
  select * into a from public.shifts where id = sw.from_shift for update;
  select * into b from public.shifts where id = sw.to_shift for update;
  if a.staff_id <> sw.from_staff or b.staff_id <> sw.to_staff or a.status not in ('assigned', 'confirmed') or b.status not in ('assigned', 'confirmed') then
    update public.shift_swaps set status = 'cancelled', decided_at = now() where id = sw.id;
    raise exception 'The rota has changed since they asked, so this swap was cancelled.';
  end if;
  perform set_config('app.swapping', '1', true);
  update public.shifts set staff_id = case when id = a.id then b.staff_id else a.staff_id end where id in (a.id, b.id);
  perform set_config('app.swapping', '', true);
  update public.shift_swaps set status = 'approved', decided_at = now() where id = sw.id;
end $$;
grant execute on function public.admin_decide_swap(bigint, boolean) to authenticated;
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
-- Member preferences: favourite nights, football team, drinks. Members can change their own; admins can read them for offers.
alter table public.profiles add column if not exists prefs jsonb;
grant update (prefs) on public.profiles to authenticated;
-- What's On (public): leave out league nights and sports-league bookings (they stay in the diary). Tournaments, competitions and cups still show.
create or replace function public.get_public_whats_on(max_rows int default 3)
returns table (title text, starts_at timestamptz, info text, kind text)
language sql stable security definer set search_path = '' as $$
  select x.title, x.starts_at, x.info, x.kind from (
    select e.title, e.starts_at, coalesce(e.category, '') as info, 'event'::text as kind
    from public.events e
    where e.starts_at >= date_trunc('day', now())
      and not (e.category = 'Sport' and coalesce(e.description, '') like 'Premier League%')
    union all
    select b.event_type,
           (b.booking_date + coalesce(b.start_time, time '19:00')) at time zone 'Europe/London',
           (case b.room when 'hall' then 'Function Room' else 'Lounge Bar' end) || (case when b.ticketed then ' · Tickets' else ' · Free entry' end),
           'club'
    from public.bookings b
    where b.booking_kind = 'club' and b.status <> 'cancelled' and b.booking_date >= current_date
      and not (coalesce((b.event_details->>'sport')::boolean, false) and b.event_type !~* '(tournament|competition|\mcomp\M|cup|final|knock-?out|\mopen\M|championship)')
  ) x
  where not (x.title ~* 'league' and x.title !~* '(tournament|competition|\mcomp\M|cup|final|knock-?out|\mopen\M|championship)')
  order by x.starts_at
  limit least(greatest(coalesce(max_rows, 3), 1), 10);
$$;
grant execute on function public.get_public_whats_on(int) to anon, authenticated;
-- =====================================================================
-- Swap requests to everyone, and holiday only before the rota is out.
-- Run after update-rota-periods.sql.
-- =====================================================================

-- A staff member asks everyone to swap one of their shifts
create table if not exists public.swap_requests (
  id          bigint generated always as identity primary key,
  shift_id    bigint not null references public.shifts on delete cascade,
  staff_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  note        text,
  status      text not null default 'open' check (status in ('open', 'matched', 'cancelled')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
create unique index if not exists swap_requests_one_open on public.swap_requests (shift_id) where status = 'open';
alter table public.swap_requests enable row level security;
drop policy if exists "staff see swap requests" on public.swap_requests;
create policy "staff see swap requests" on public.swap_requests
  for select to authenticated using (public.is_staff_or_admin());

-- Colleagues offer one of their shifts back, or say no thanks (shift_id empty)
create table if not exists public.swap_offers (
  id          bigint generated always as identity primary key,
  request_id  bigint not null references public.swap_requests on delete cascade,
  shift_id    bigint references public.shifts on delete cascade,
  staff_id    uuid not null default auth.uid() references public.profiles on delete cascade,
  status      text not null default 'offered' check (status in ('offered', 'passed', 'accepted', 'declined', 'withdrawn')),
  created_at  timestamptz not null default now()
);
create unique index if not exists swap_offers_one_each on public.swap_offers (request_id, staff_id) where status in ('offered', 'passed', 'accepted');
alter table public.swap_offers enable row level security;
drop policy if exists "people involved see swap offers" on public.swap_offers;
create policy "people involved see swap offers" on public.swap_offers
  for select to authenticated using (
    staff_id = auth.uid() or public.is_admin()
    or exists (select 1 from public.swap_requests r where r.id = request_id and r.staff_id = auth.uid()));

-- Ask everyone
create or replace function public.staff_ask_swap_all(my_shift bigint, why text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare a public.shifts; new_id bigint;
begin
  select * into a from public.shifts where id = my_shift;
  if a.id is null or a.staff_id <> auth.uid() or a.status not in ('assigned', 'confirmed') then raise exception 'That isn''t one of your shifts.'; end if;
  if a.shift_date <= current_date then raise exception 'Swaps need to be for tomorrow or later.'; end if;
  if not public.rota_published(a.shift_date) then raise exception 'That rota isn''t published yet.'; end if;
  if exists (select 1 from public.shift_swaps where status in ('asked', 'accepted') and a.id in (from_shift, to_shift)) then
    raise exception 'This shift already has a swap waiting.'; end if;
  insert into public.swap_requests (shift_id, staff_id, note) values (a.id, auth.uid(), nullif(trim(why), '')) returning id into new_id;
  return new_id;
exception when unique_violation then raise exception 'You''ve already asked everyone to swap this shift.';
end $$;
grant execute on function public.staff_ask_swap_all(bigint, text) to authenticated;

create or replace function public.staff_cancel_swap_request(req bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.swap_requests set status = 'cancelled', decided_at = now() where id = req and staff_id = auth.uid() and status = 'open';
  if not found then raise exception 'That request has already closed.'; end if;
  update public.swap_offers set status = 'declined' where request_id = req and status = 'offered';
end $$;
grant execute on function public.staff_cancel_swap_request(bigint) to authenticated;

-- Offer one of my shifts in exchange
create or replace function public.staff_offer_swap(req bigint, my_shift bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare r public.swap_requests; a public.shifts; b public.shifts; sa text; sb text; new_id bigint;
begin
  select * into r from public.swap_requests where id = req;
  if r.id is null or r.status <> 'open' then raise exception 'That request has closed.'; end if;
  select * into a from public.shifts where id = r.shift_id;          -- their shift
  select * into b from public.shifts where id = my_shift;            -- my shift
  if b.id is null or b.staff_id <> auth.uid() or b.status not in ('assigned', 'confirmed') then raise exception 'That isn''t one of your shifts.'; end if;
  if r.staff_id = auth.uid() then raise exception 'That''s your own request.'; end if;
  if b.shift_date <= current_date or not public.rota_published(b.shift_date) then raise exception 'Pick a shift from tomorrow on the published rota.'; end if;
  if a.shift_date = b.shift_date then raise exception 'Pick a shift on a different day.'; end if;
  if exists (select 1 from public.shifts where staff_id = auth.uid() and shift_date = a.shift_date and status in ('assigned', 'confirmed', 'late')) then raise exception 'You''re already working that day.'; end if;
  if exists (select 1 from public.shifts where staff_id = r.staff_id and shift_date = b.shift_date and status in ('assigned', 'confirmed', 'late')) then raise exception 'They''re already working on your day.'; end if;
  select skill into sa from public.profiles where id = r.staff_id;
  select skill into sb from public.profiles where id = auth.uid();
  if not public.can_do_job(sb, a.job) or not public.can_do_job(sa, b.job) then raise exception 'You can''t both do each other''s jobs.'; end if;
  update public.swap_offers set status = 'withdrawn' where request_id = req and staff_id = auth.uid() and status = 'passed';
  insert into public.swap_offers (request_id, shift_id, staff_id) values (req, b.id, auth.uid()) returning id into new_id;
  return new_id;
exception when unique_violation then raise exception 'You''ve already answered this one.';
end $$;
grant execute on function public.staff_offer_swap(bigint, bigint) to authenticated;

create or replace function public.staff_pass_swap(req bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.swap_offers (request_id, staff_id, status) values (req, auth.uid(), 'passed');
exception when unique_violation then null;
end $$;
grant execute on function public.staff_pass_swap(bigint) to authenticated;

create or replace function public.staff_withdraw_swap_offer(offer bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.swap_offers set status = 'withdrawn' where id = offer and staff_id = auth.uid() and status = 'offered';
  if not found then raise exception 'That offer has already been answered.'; end if;
end $$;
grant execute on function public.staff_withdraw_swap_offer(bigint) to authenticated;

-- The person who asked picks one offer. It then goes to the manager (Swaps to approve).
create or replace function public.staff_accept_swap_offer(offer bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare o public.swap_offers; r public.swap_requests; a public.shifts; b public.shifts;
begin
  select * into o from public.swap_offers where id = offer for update;
  select * into r from public.swap_requests where id = o.request_id for update;
  if o.id is null or r.staff_id <> auth.uid() then raise exception 'Offer not found.'; end if;
  if r.status <> 'open' or o.status <> 'offered' then raise exception 'That offer is no longer open.'; end if;
  select * into a from public.shifts where id = r.shift_id;
  select * into b from public.shifts where id = o.shift_id;
  if a.staff_id <> r.staff_id or b.staff_id <> o.staff_id or a.status not in ('assigned', 'confirmed') or b.status not in ('assigned', 'confirmed') then
    update public.swap_offers set status = 'declined' where id = o.id;
    raise exception 'The rota has changed, so that offer can''t be used.';
  end if;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note, status)
  values (a.id, b.id, r.staff_id, o.staff_id, r.note, 'accepted');
  update public.swap_offers set status = case when id = o.id then 'accepted' else 'declined' end where request_id = r.id and status = 'offered';
  update public.swap_requests set status = 'matched', decided_at = now() where id = r.id;
end $$;
grant execute on function public.staff_accept_swap_offer(bigint) to authenticated;

-- Holiday: only for days whose rota isn't out yet (once it's out, swap your shifts instead)
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
  for yr, n in select extract(year from d)::int, count(*) from unnest(picked) d group by 1 loop
    if public.holiday_days_taken(auth.uid(), yr) + n > 28 then
      raise exception 'That would go over your 28 days for %. You have % left.', yr, greatest(0, 28 - public.holiday_days_taken(auth.uid(), yr));
    end if;
  end loop;
  insert into public.holiday_requests (staff_id, days, note) values (auth.uid(), picked, nullif(trim(why), '')) returning id into new_id;
  return new_id;
end $$;
grant execute on function public.staff_request_holiday(date[], text) to authenticated;
-- Part-time staff: the days they can usually work (the rota lists them first on those days, marked "can work")
alter table public.profiles add column if not exists avail_days jsonb not null default '[]'::jsonb;

create or replace function public.admin_set_avail(pid uuid, days jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  if jsonb_typeof(days) <> 'array' or exists (select 1 from jsonb_array_elements_text(days) d where d !~ '^[0-6]$') then raise exception 'Those days aren''t valid.'; end if;
  update public.profiles set avail_days = days where id = pid;
end $$;
grant execute on function public.admin_set_avail(uuid, jsonb) to authenticated;

-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat
update public.profiles set avail_days = '[5,6,0]' where email = 'yan@arcstaff.test';        -- Yan: Fri, Sat, Sun
update public.profiles set avail_days = '[1,3,4]' where email = 'heather@arcstaff.test';    -- Heather: Mon, Wed, Thu
update public.profiles set avail_days = '[2,4,6]' where email = 'ben@arcstaff.test';        -- Ben: Tue, Thu, Sat
update public.profiles set avail_days = '[3,5,0]' where email = 'mark@railway.com';         -- Mark: Wed, Fri, Sun
update public.profiles set avail_days = '[1,2,6]' where email = 'staff@railway.com';        -- Staff Member: Mon, Tue, Sat

-- Check
select first_name, skill, jsonb_array_length(regular_shifts) as regular_shifts_a_week, avail_days as can_work_days
from public.profiles where role in ('staff', 'admin') and skill is not null order by regular_shifts_a_week desc, first_name;
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
-- =====================================================================
-- Club membership register, Going / Interested on What's On, and Friends.
-- Friends are added by membership number and must accept the request.
-- =====================================================================

-- 1) Membership register: every club member (whether or not they use the app)
create table if not exists public.club_members (
  membership_no  text primary key check (membership_no ~ '^[A-Za-z0-9-]{2,20}$'),
  first_name     text not null,
  last_name      text not null,
  tier           text,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);
alter table public.club_members enable row level security;
drop policy if exists "admins manage the register" on public.club_members;
create policy "admins manage the register" on public.club_members for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 2) Going / Interested. event_key: 'b<booking id>' for club events, 'e<event id>' for What's On items
create table if not exists public.event_rsvps (
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  event_key  text not null check (event_key ~ '^[be][0-9]+$'),
  event_date date not null,
  status     text not null check (status in ('going', 'interested')),
  created_at timestamptz not null default now(),
  primary key (user_id, event_key)
);
create index if not exists event_rsvps_key_idx on public.event_rsvps (event_key);
alter table public.event_rsvps enable row level security;
drop policy if exists "own rsvps, admins all" on public.event_rsvps;
create policy "own rsvps, admins all" on public.event_rsvps for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "members set their own rsvps" on public.event_rsvps;
create policy "members set their own rsvps" on public.event_rsvps for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Counts for each event (no names)
create or replace function public.get_rsvp_counts(keys text[])
returns table (event_key text, going int, interested int)
language sql stable security definer set search_path = '' as $$
  select r.event_key, count(*) filter (where r.status = 'going')::int, count(*) filter (where r.status = 'interested')::int
  from public.event_rsvps r where r.event_key = any(keys) group by r.event_key;
$$;
grant execute on function public.get_rsvp_counts(text[]) to authenticated;

-- 3) Friends
create table if not exists public.friendships (
  id          bigint generated always as identity primary key,
  requester   uuid not null default auth.uid() references public.profiles on delete cascade,
  addressee   uuid not null references public.profiles on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  likes       text[] not null default '{}',          -- event types they share, e.g. {bingo,quiz}
  created_at  timestamptz not null default now(),
  check (requester <> addressee)
);
create unique index if not exists friendships_pair on public.friendships (least(requester, addressee), greatest(requester, addressee));
alter table public.friendships enable row level security;
drop policy if exists "people in the friendship see it" on public.friendships;
create policy "people in the friendship see it" on public.friendships for select to authenticated using (requester = auth.uid() or addressee = auth.uid());
-- (changes go through the functions below)

-- Look up a membership number: first name and surname initial only.
-- An app account only counts as that member if its surname matches the register (stops people claiming someone else's number).
create or replace function public.find_member(no text)
returns table (first_name text, last_initial text, on_app boolean)
language sql stable security definer set search_path = '' as $$
  with reg as (select c.first_name, c.last_name from public.club_members c where upper(c.membership_no) = upper(trim(no)) and c.active),
       app as (select p.id, p.first_name, p.last_name from public.profiles p where upper(p.membership_no) = upper(trim(no)) and p.id <> auth.uid() and not exists (select 1 from public.club_members c where upper(c.membership_no) = upper(p.membership_no) and lower(c.last_name) <> lower(coalesce(p.last_name, ''))) limit 1)
  select coalesce((select first_name from reg), (select first_name from app)),
         left(coalesce((select last_name from reg), (select last_name from app), ''), 1),
         exists (select 1 from app)
  where auth.uid() is not null and (exists (select 1 from reg) or exists (select 1 from app));
$$;
grant execute on function public.find_member(text) to authenticated;

create or replace function public.send_friend_request(no text, shared text[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
declare them uuid;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  select p.id into them from public.profiles p where upper(p.membership_no) = upper(trim(no)) and p.id <> auth.uid() and not exists (select 1 from public.club_members c where upper(c.membership_no) = upper(p.membership_no) and lower(c.last_name) <> lower(coalesce(p.last_name, ''))) limit 1;
  if them is null then raise exception 'That member isn''t on the app yet. Ask them to register with their membership number.'; end if;
  insert into public.friendships (requester, addressee, likes) values (auth.uid(), them, coalesce(shared, '{}'))
  on conflict (least(requester, addressee), greatest(requester, addressee))
  do update set likes = excluded.likes, status = case when public.friendships.status = 'declined' then 'pending' else public.friendships.status end,
                requester = case when public.friendships.status = 'declined' then excluded.requester else public.friendships.requester end,
                addressee = case when public.friendships.status = 'declined' then excluded.addressee else public.friendships.addressee end;
end $$;
grant execute on function public.send_friend_request(text, text[]) to authenticated;

create or replace function public.answer_friend(fid bigint, yes boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.friendships set status = case when yes then 'accepted' else 'declined' end where id = fid and addressee = auth.uid() and status = 'pending';
  if not found then raise exception 'That request has already been answered.'; end if;
end $$;
grant execute on function public.answer_friend(bigint, boolean) to authenticated;

create or replace function public.update_friend_likes(fid bigint, shared text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.friendships set likes = coalesce(shared, '{}') where id = fid and auth.uid() in (requester, addressee);
end $$;
grant execute on function public.update_friend_likes(bigint, text[]) to authenticated;

create or replace function public.remove_friend(fid bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.friendships where id = fid and auth.uid() in (requester, addressee);
end $$;
grant execute on function public.remove_friend(bigint) to authenticated;

-- My friends and requests, with names
create or replace function public.my_friends()
returns table (id bigint, other uuid, first_name text, last_initial text, status text, incoming boolean, likes text[])
language sql stable security definer set search_path = '' as $$
  select f.id, o.id, o.first_name, left(coalesce(o.last_name, ''), 1), f.status, f.addressee = auth.uid(), f.likes
  from public.friendships f
  join public.profiles o on o.id = case when f.requester = auth.uid() then f.addressee else f.requester end
  where auth.uid() in (f.requester, f.addressee) and f.status <> 'declined';
$$;
grant execute on function public.my_friends() to authenticated;

-- What my friends are going to / interested in
drop function if exists public.friends_rsvps(date);
create or replace function public.friends_rsvps(from_date date)
returns table (event_key text, who uuid, first_name text, status text)
language sql stable security definer set search_path = '' as $$
  select r.event_key, r.user_id, p.first_name, r.status
  from public.friendships f
  join public.event_rsvps r on r.user_id = case when f.requester = auth.uid() then f.addressee else f.requester end
  join public.profiles p on p.id = r.user_id
  where f.status = 'accepted' and auth.uid() in (f.requester, f.addressee) and r.event_date >= from_date;
$$;
grant execute on function public.friends_rsvps(date) to authenticated;
-- Members' message board: friends can send each other short messages. Run after update-friends-going.sql.
create table if not exists public.member_messages (
  id          bigint generated always as identity primary key,
  sender      uuid not null default auth.uid() references public.profiles on delete cascade,
  recipient   uuid not null references public.profiles on delete cascade,
  body        text not null check (length(trim(body)) between 1 and 500),
  read_at     timestamptz,
  created_at  timestamptz not null default now(),
  check (sender <> recipient)
);
create index if not exists member_messages_recipient_idx on public.member_messages (recipient, created_at desc);
create index if not exists member_messages_sender_idx on public.member_messages (sender, created_at desc);
alter table public.member_messages enable row level security;

-- Are these two people friends?
create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.friendships f where f.status = 'accepted'
                 and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a)));
$$;

drop policy if exists "people in the conversation see it" on public.member_messages;
create policy "people in the conversation see it" on public.member_messages
  for select to authenticated using (sender = auth.uid() or recipient = auth.uid());
drop policy if exists "members message their friends" on public.member_messages;
create policy "members message their friends" on public.member_messages
  for insert to authenticated with check (sender = auth.uid() and read_at is null and public.are_friends(sender, recipient));
drop policy if exists "people delete their own messages" on public.member_messages;
create policy "people delete their own messages" on public.member_messages
  for delete to authenticated using (sender = auth.uid() or recipient = auth.uid());

-- Mark everything from one friend as read
create or replace function public.mark_messages_read(friend uuid)
returns void language sql security definer set search_path = '' as $$
  update public.member_messages set read_at = now() where recipient = auth.uid() and sender = friend and read_at is null;
$$;
grant execute on function public.mark_messages_read(uuid) to authenticated;
-- Online card payments (Stripe): payments can be marked 'online', and each Stripe payment is only recorded once.
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check check (method in ('cash', 'card', 'bank', 'other', 'online'));
alter table public.payments add column if not exists stripe_ref text;
create unique index if not exists payments_stripe_ref on public.payments (stripe_ref);
alter table public.ticket_reservations add column if not exists stripe_session text;
-- Payment deadlines: remember when a booking was confirmed (the 7-day deposit clock starts then)
alter table public.bookings add column if not exists confirmed_at timestamptz;
update public.bookings set confirmed_at = created_at where status = 'confirmed' and confirmed_at is null;
create or replace function public.bookings_confirmed_at() returns trigger language plpgsql as $$
begin
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from 'confirmed') then new.confirmed_at := now(); end if;
  return new;
end $$;
drop trigger if exists bookings_confirmed_at on public.bookings;
create trigger bookings_confirmed_at before insert or update of status on public.bookings for each row execute function public.bookings_confirmed_at();
-- =====================================================================
-- Roles (App admin, Secretary, Bar Manager, Entertainments, Staff, Member),
-- club notices to members, and Jobs (staff wanted).
-- =====================================================================

-- 1) Job title and access areas on each account
alter table public.profiles add column if not exists title text;
alter table public.profiles add column if not exists perms text[] not null default '{}';

-- Has the signed-in person got this permission? The app admin ('owner') has every permission.
create or replace function public.has_perm(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and (p = any(perms) or 'owner' = any(perms)));
$$;
grant execute on function public.has_perm(text) to authenticated;

-- Only the app admin can give or take away admin-level roles
create or replace function public.admin_set_access(pid uuid, new_role text, new_title text, new_perms text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_perm('owner') then raise exception 'Only the app admin can change roles.'; end if;
  if new_role not in ('user', 'staff', 'admin') then raise exception 'Unknown role.'; end if;
  if pid = auth.uid() and not ('owner' = any(coalesce(new_perms, '{}'))) then raise exception 'You can’t remove your own app admin access.'; end if;
  update public.profiles set role = new_role, title = nullif(trim(new_title), ''), perms = coalesce(new_perms, '{}'),
    skill = case when new_role = 'user' then null when new_role = 'staff' then coalesce(skill, 'both') else skill end
  where id = pid;
end $$;
grant execute on function public.admin_set_access(uuid, text, text, text[]) to authenticated;

-- Other admins can still make people staff or members, but not admins
create or replace function public.admin_set_profile(pid uuid, new_role text, new_skill text)
returns void language plpgsql security definer set search_path = '' as $$
declare cur text;
begin
  if not public.is_admin() then raise exception 'Only admins can change accounts.'; end if;
  select role into cur from public.profiles where id = pid;
  if (new_role = 'admin' or cur = 'admin') and new_role is distinct from cur and not public.has_perm('owner') then
    raise exception 'Only the app admin can give or remove admin roles.'; end if;
  if pid = auth.uid() and new_role <> 'admin' then raise exception 'You can’t remove your own admin access.'; end if;
  update public.profiles set
    role  = new_role,
    skill = case when new_role = 'user' then null when new_role = 'staff' then coalesce(new_skill, 'both') else new_skill end
  where id = pid;
  if new_role = 'user' or (new_role = 'admin' and new_skill is null) then
    delete from public.shifts where staff_id = pid and shift_date >= current_date;
    update public.profiles set regular_shifts = '[]'::jsonb where id = pid;
  end if;
end $$;

-- Entertainments committee can manage What's On
drop policy if exists "whats on editors manage events" on public.events;
create policy "whats on editors manage events" on public.events
  for all to authenticated using (public.has_perm('whatson')) with check (public.has_perm('whatson'));

-- 2) Notices from the club
create table if not exists public.club_notices (
  id          bigint generated always as identity primary key,
  title       text not null check (length(title) between 1 and 120),
  body        text not null check (length(body) between 1 and 1500),
  audience    text not null default 'all' check (audience in ('all', 'members', 'staff')),
  job_id      bigint,
  created_by  uuid default auth.uid() references auth.users on delete set null,
  created_at  timestamptz not null default now()
);
alter table public.club_notices enable row level security;
drop policy if exists "everyone signed in reads notices" on public.club_notices;
create policy "everyone signed in reads notices" on public.club_notices for select to authenticated using (true);
drop policy if exists "admins send notices" on public.club_notices;
create policy "admins send notices" on public.club_notices for all to authenticated using (public.is_admin()) with check (public.is_admin());

create table if not exists public.notice_reads (
  user_id   uuid not null default auth.uid() references auth.users on delete cascade,
  notice_id bigint not null references public.club_notices on delete cascade,
  read_at   timestamptz not null default now(),
  primary key (user_id, notice_id)
);
alter table public.notice_reads enable row level security;
drop policy if exists "own reads, admins count" on public.notice_reads;
create policy "own reads, admins count" on public.notice_reads for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "mark own reads" on public.notice_reads;
create policy "mark own reads" on public.notice_reads for insert to authenticated with check (user_id = auth.uid());

-- 3) Jobs: staff wanted
create table if not exists public.jobs (
  id          bigint generated always as identity primary key,
  title       text not null check (length(title) between 1 and 100),
  job_type    text,                 -- e.g. Part time, Full time, Casual
  hours       text,
  pay         text,
  description text not null default '',
  closes_on   date,
  status      text not null default 'open' check (status in ('open', 'closed')),
  created_at  timestamptz not null default now()
);
alter table public.jobs enable row level security;
drop policy if exists "everyone sees open jobs" on public.jobs;
create policy "everyone sees open jobs" on public.jobs for select to authenticated using (status = 'open' or public.is_admin());
drop policy if exists "admins manage jobs" on public.jobs;
create policy "admins manage jobs" on public.jobs for all to authenticated using (public.is_admin()) with check (public.is_admin());

create table if not exists public.job_applications (
  id          bigint generated always as identity primary key,
  job_id      bigint not null references public.jobs on delete cascade,
  user_id     uuid not null default auth.uid() references public.profiles on delete cascade,
  note        text check (note is null or length(note) <= 600),
  phone       text,
  created_at  timestamptz not null default now(),
  unique (job_id, user_id)
);
alter table public.job_applications enable row level security;
drop policy if exists "own applications, admins all" on public.job_applications;
create policy "own applications, admins all" on public.job_applications for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "members apply" on public.job_applications;
create policy "members apply" on public.job_applications for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "members withdraw" on public.job_applications;
create policy "members withdraw" on public.job_applications for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- Names and contact details of applicants, for admins
create or replace function public.job_applicants(jid bigint)
returns table (id bigint, user_id uuid, first_name text, last_name text, email text, phone text, membership_no text, note text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id, a.user_id, p.first_name, p.last_name, p.email, coalesce(a.phone, p.phone), p.membership_no, a.note, a.created_at
  from public.job_applications a join public.profiles p on p.id = a.user_id
  where a.job_id = jid and public.is_admin() order by a.created_at;
$$;
grant execute on function public.job_applicants(bigint) to authenticated;

-- 4) Make Mark the app admin (sees everything, can switch views, gives out roles)
update public.profiles set role = 'admin', title = 'App admin', perms = array['owner']
where lower(email) = 'markgoulding180@gmail.com';
select first_name, email, role, title, perms from public.profiles where lower(email) = 'markgoulding180@gmail.com';
