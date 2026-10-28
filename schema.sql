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
