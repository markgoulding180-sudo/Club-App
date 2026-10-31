-- =====================================================================
-- Phone notifications (free Web Push): new events, newsletter, booking confirmed,
-- messages, notices, and a reminder 1 hour before events a member is going to or likes.
-- Run this AFTER creating the send-push function in Supabase (see PUSH-SETUP.md).
-- Safe to run again.
-- =====================================================================
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- 1) Settings only the server can read (notification keys are made by send-push on its first run)
create table if not exists public.push_config (key text primary key, value text not null);
alter table public.push_config enable row level security;   -- no policies: hidden from the app
insert into public.push_config (key, value) values ('cron_key', encode(extensions.gen_random_bytes(24), 'hex')) on conflict (key) do nothing;
insert into public.push_config (key, value) values ('contact', 'mailto:markgoulding180@gmail.com') on conflict (key) do nothing;

-- The app needs the public key to sign a phone up
create or replace function public.push_public_key() returns text
language sql stable security definer set search_path = '' as $$ select value from public.push_config where key = 'vapid_public' $$;
grant execute on function public.push_public_key() to anon, authenticated;

-- 2) Phones signed up for notifications
create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  user_id    uuid not null references public.profiles on delete cascade,
  p256dh     text not null,
  auth       text not null,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;
drop policy if exists "own phones" on public.push_subscriptions;
create policy "own phones" on public.push_subscriptions for select to authenticated using (user_id = auth.uid());

drop function if exists public.save_push_sub(text, text, text);
create or replace function public.save_push_sub(p_endpoint text, p_key text, p_secret text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if p_endpoint !~ '^https://' or length(p_endpoint) > 1000 then raise exception 'That isn''t a valid phone.'; end if;
  insert into public.push_subscriptions (endpoint, user_id, p256dh, auth) values (p_endpoint, auth.uid(), p_key, p_secret)
  on conflict (endpoint) do update set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth;
end $$;
grant execute on function public.save_push_sub(text, text, text) to authenticated;
drop function if exists public.remove_push_sub(text);
create or replace function public.remove_push_sub(p_endpoint text) returns void
language sql security definer set search_path = '' as $$ delete from public.push_subscriptions s where s.endpoint = p_endpoint and s.user_id = auth.uid() $$;
grant execute on function public.remove_push_sub(text) to authenticated;

-- What each person wants to hear about (all on to start with)
alter table public.profiles add column if not exists push_prefs jsonb not null
  default '{"events":true,"news":true,"bookings":true,"messages":true,"reminders":true}'::jsonb;
create or replace function public.set_push_prefs(p jsonb) returns void
language sql security definer set search_path = '' as $$
  update public.profiles set push_prefs = jsonb_build_object(
    'events', coalesce((p->>'events')::boolean, true), 'news', coalesce((p->>'news')::boolean, true),
    'bookings', coalesce((p->>'bookings')::boolean, true), 'messages', coalesce((p->>'messages')::boolean, true),
    'reminders', coalesce((p->>'reminders')::boolean, true)) where id = auth.uid();
$$;
grant execute on function public.set_push_prefs(jsonb) to authenticated;

-- 3) Waiting notifications (filled by the triggers below, sent by send-push)
create table if not exists public.push_queue (
  id         bigint generated always as identity primary key,
  kind       text not null check (kind in ('events', 'news', 'bookings', 'messages', 'reminders')),
  audience   text not null check (audience in ('user', 'members', 'staff', 'all')),
  user_id    uuid references public.profiles on delete cascade,
  title      text not null,
  body       text not null default '',
  url        text not null default '/',
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);
create index if not exists push_queue_unsent_idx on public.push_queue (id) where sent_at is null;
alter table public.push_queue enable row level security;     -- no policies: server only
create table if not exists public.push_reminded (event_key text primary key, sent_at timestamptz not null default now());
alter table public.push_reminded enable row level security;

create or replace function public.push_when(d date, t time) returns text
language sql immutable set search_path = '' as $$
  select trim(to_char(d, 'Dy FMDD Mon')) || coalesce(', ' || lower(trim(to_char(t, 'FMHH12:MIam'))), '') $$;

-- League nights stay quiet (they're not on What's On either)
create or replace function public.push_is_league(name text, details jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select (coalesce(name, '') ~* 'league' or coalesce((details->>'sport')::boolean, false))
     and coalesce(name, '') !~* '(tournament|competition|\mcomp\M|cup|final|knock-?out|\mopen\M|championship)' $$;

-- New club event, or a member's booking confirmed
create or replace function public.push_on_booking() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.booking_kind = 'club' and new.status <> 'cancelled' and new.booking_date >= current_date
     and not public.push_is_league(new.event_type, new.event_details) then
    insert into public.push_queue (kind, audience, title, body, url)
    values ('events', 'members', 'New at the club: ' || coalesce(new.event_type, 'event'),
            public.push_when(new.booking_date, new.start_time) || case when new.ticketed then '. Tickets in the app.' else '. Tap to see What''s On.' end, '/?go=whatson');
  elsif tg_op = 'UPDATE' and new.booking_kind = 'member' and new.user_id is not null
        and new.status = 'confirmed' and old.status is distinct from 'confirmed' then
    insert into public.push_queue (kind, audience, user_id, title, body, url)
    values ('bookings', 'user', new.user_id, 'Your booking is confirmed ✅',
            case new.room when 'hall' then 'Function Room' else 'Lounge Bar' end || ', ' || public.push_when(new.booking_date, null) || ' (' || new.slot || ')', '/?go=mine');
  end if;
  return new;
end $$;
drop trigger if exists push_on_booking on public.bookings;
create trigger push_on_booking after insert or update of status on public.bookings for each row execute function public.push_on_booking();

-- New What's On item (not football fixtures)
create or replace function public.push_on_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.starts_at > now() and coalesce(new.description, '') not like 'Premier League%' and not public.push_is_league(new.title, null) then
    insert into public.push_queue (kind, audience, title, body, url)
    values ('events', 'members', 'New at the club: ' || new.title,
            public.push_when((new.starts_at at time zone 'Europe/London')::date, (new.starts_at at time zone 'Europe/London')::time) || '. Tap to see What''s On.', '/?go=whatson');
  end if;
  return new;
end $$;
drop trigger if exists push_on_event on public.events;
create trigger push_on_event after insert on public.events for each row execute function public.push_on_event();

-- Newsletter published
create or replace function public.push_on_newsletter() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.published_at is not null and (tg_op = 'INSERT' or old.published_at is null) then
    insert into public.push_queue (kind, audience, title, body, url)
    values ('news', 'all', 'The ' || new.title || ' newsletter is out 📰', left(coalesce(nullif(new.intro, ''), 'News from the club.'), 140), '/?go=news');
  end if;
  return new;
end $$;
drop trigger if exists push_on_newsletter on public.newsletters;
create trigger push_on_newsletter after insert or update of published_at on public.newsletters for each row execute function public.push_on_newsletter();

-- Notice from the club (the "newsletter is out" notice is skipped, the newsletter already sends one)
create or replace function public.push_on_notice() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.title not like 'Newsletter:%' then
    insert into public.push_queue (kind, audience, title, body, url)
    values ('news', case new.audience when 'members' then 'members' when 'staff' then 'staff' else 'all' end, '📢 ' || new.title, left(new.body, 140), '/?go=notices');
  end if;
  return new;
end $$;
drop trigger if exists push_on_notice on public.club_notices;
create trigger push_on_notice after insert on public.club_notices for each row execute function public.push_on_notice();

-- New message on the message board
create or replace function public.push_on_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare who text;
begin
  select case when p.role = 'admin' then 'Railway Club' || coalesce(' · ' || p.title, '') else coalesce(p.first_name, 'A friend') end into who
  from public.profiles p where p.id = new.sender;
  insert into public.push_queue (kind, audience, user_id, title, body, url)
  values ('messages', 'user', new.recipient, 'Message from ' || coalesce(who, 'a friend'), left(new.body, 140), '/?go=friends');
  return new;
end $$;
drop trigger if exists push_on_message on public.member_messages;
create trigger push_on_message after insert on public.member_messages for each row execute function public.push_on_message();

-- 4) "Starts in 1 hour": members who said Going/Interested, or who picked that kind of night in their preferences
create or replace function public.push_queue_reminders() returns int
language plpgsql security definer set search_path = '' as $$
declare e record; n int := 0;
begin
  for e in
    select 'b' || b.id as k, b.event_type as title, b.booking_date as d, b.start_time as t, b.event_details->>'cat' as cat
    from public.bookings b
    where b.booking_kind = 'club' and b.status = 'confirmed' and b.start_time is not null
      and b.booking_date between current_date and current_date + 1
      and ((b.booking_date + b.start_time) at time zone 'Europe/London') between now() and now() + interval '60 minutes'
      and not public.push_is_league(b.event_type, b.event_details)
    union all
    select 'e' || v.id, v.title, (v.starts_at at time zone 'Europe/London')::date, (v.starts_at at time zone 'Europe/London')::time, null
    from public.events v
    where v.starts_at between now() and now() + interval '60 minutes' and coalesce(v.description, '') not like 'Premier League%'
  loop
    continue when exists (select 1 from public.push_reminded r where r.event_key = e.k);
    insert into public.push_reminded (event_key) values (e.k);
    insert into public.push_queue (kind, audience, user_id, title, body, url)
    select 'reminders', 'user', p.id, e.title || ' starts at ' || lower(trim(to_char(e.t, 'FMHH12:MIam'))), 'See you at the club tonight 🍻', '/?go=whatson'
    from public.profiles p
    where p.role = 'user' and (
      exists (select 1 from public.event_rsvps r where r.user_id = p.id and r.event_key = e.k)
      or (e.cat is not null and e.cat <> 'none' and coalesce(p.prefs->'cats', '[]'::jsonb) ? e.cat));
    n := n + 1;
  end loop;
  delete from public.push_reminded where sent_at < now() - interval '3 days';
  return n;
end $$;

-- 5) For send-push only: take the waiting notifications, matched to each person's phones and choices
create or replace function public.push_take_batch()
returns table (kind text, title text, body text, url text, endpoint text, p256dh text, auth text)
language sql security definer set search_path = '' as $$
  with q as (
    update public.push_queue set sent_at = now()
    where id in (select id from public.push_queue where sent_at is null order by id limit 300)
    returning *
  ), who as (
    select q.*, p.id as uid from q join public.profiles p on
      (q.audience = 'user' and p.id = q.user_id) or (q.audience = 'members' and p.role = 'user')
      or (q.audience = 'staff' and p.role = 'staff') or (q.audience = 'all' and p.role in ('user', 'staff'))
    where coalesce((p.push_prefs->>q.kind)::boolean, true) and q.created_at > now() - interval '1 day'
  )
  select w.kind, w.title, w.body, w.url, s.endpoint, s.p256dh, s.auth
  from who w join public.push_subscriptions s on s.user_id = w.uid order by w.id;
$$;
create or replace function public.push_drop_subs(endpoints text[]) returns void
language sql security definer set search_path = '' as $$ delete from public.push_subscriptions where endpoint = any(endpoints) $$;
revoke all on function public.push_take_batch() from public, anon, authenticated;
revoke all on function public.push_drop_subs(text[]) from public, anon, authenticated;
revoke all on function public.push_queue_reminders() from public, anon, authenticated;
grant execute on function public.push_take_batch() to service_role;
grant execute on function public.push_drop_subs(text[]) to service_role;

-- 6) Every minute: queue the 1-hour reminders, then call send-push if there's anything to send
do $$ begin perform cron.unschedule('club-push'); exception when others then null; end $$;
select cron.schedule('club-push', '* * * * *', $job$
  select public.push_queue_reminders();
  select net.http_post(
    url := 'https://tvflgseltbjnkxyfjlem.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-key', (select value from public.push_config where key = 'cron_key')),
    body := '{}'::jsonb, timeout_milliseconds := 25000)
  where exists (select 1 from public.push_queue where sent_at is null)
     or not exists (select 1 from public.push_config where key = 'vapid_public');
$job$);

-- Check (after a minute, vapid_public should appear)
select key, case when key = 'vapid_public' then left(value, 20) || '…' else 'set' end from public.push_config order by key;
