-- Newsletter: a monthly newsletter members read under News, with pictures.
-- Admins with the Notices area (App admin, Secretary, Bar Manager) write and publish it.
create table if not exists public.newsletters (
  id           bigint generated always as identity primary key,
  title        text not null check (length(title) between 1 and 120),
  issue_date   date not null default current_date,
  intro        text not null default '' check (length(intro) <= 1000),
  cover_url    text,
  sections     jsonb not null default '[]'::jsonb check (jsonb_typeof(sections) = 'array'),  -- [{h, body, img}]
  published_at timestamptz,
  created_by   uuid default auth.uid() references auth.users on delete set null,
  created_at   timestamptz not null default now()
);
alter table public.newsletters enable row level security;
drop policy if exists "members read published newsletters" on public.newsletters;
create policy "members read published newsletters" on public.newsletters
  for select to authenticated using (published_at is not null or public.is_admin());
drop policy if exists "news editors manage newsletters" on public.newsletters;
create policy "news editors manage newsletters" on public.newsletters
  for all to authenticated using (public.is_admin() and (public.has_perm('notices') or not exists (select 1 from public.profiles p where p.id = auth.uid() and p.perms && array['bookings','rota','staff','tickets','whatson','messages','register','jobs'])))
  with check (public.is_admin() and (public.has_perm('notices') or not exists (select 1 from public.profiles p where p.id = auth.uid() and p.perms && array['bookings','rota','staff','tickets','whatson','messages','register','jobs'])));

-- Pictures: a public storage folder; only admins can upload or remove
insert into storage.buckets (id, name, public) values ('newsletter', 'newsletter', true)
on conflict (id) do update set public = true;
drop policy if exists "anyone views newsletter pictures" on storage.objects;
create policy "anyone views newsletter pictures" on storage.objects for select using (bucket_id = 'newsletter');
drop policy if exists "admins upload newsletter pictures" on storage.objects;
create policy "admins upload newsletter pictures" on storage.objects for insert to authenticated with check (bucket_id = 'newsletter' and public.is_admin());
drop policy if exists "admins change newsletter pictures" on storage.objects;
create policy "admins change newsletter pictures" on storage.objects for update to authenticated using (bucket_id = 'newsletter' and public.is_admin());
drop policy if exists "admins remove newsletter pictures" on storage.objects;
create policy "admins remove newsletter pictures" on storage.objects for delete to authenticated using (bucket_id = 'newsletter' and public.is_admin());

-- The first issue: November 2026 (published). Safe to run again.
delete from public.newsletters where title = 'November 2026' and issue_date = date '2026-11-01';
insert into public.newsletters (title, issue_date, intro, cover_url, sections, published_at)
values ('November 2026', date '2026-11-01', 'Welcome to the first Railway Club newsletter on the new club app. Every month we’ll put the club’s news, dates and events here, so you never miss a night.', 'img/slide-hall3-1400.webp', '[{"h": "A word from the Secretary", "img": "img/slide-bar-800.webp", "body": "Hello everyone.\n\nThe nights are drawing in and the club is busier than ever. This month we’ve moved bookings, tickets and What’s On onto the club app, so you can see what’s on, reserve tickets and book a room from your phone.\n\nIf you’d like a hand getting set up, just ask any of the bar staff.\n\nThank you for your support.\nStuart Fraser, Club Secretary"}, {"h": "Coming up in November", "img": "img/slide-band-800.webp", "body": "Sat 7 Nov · Race Night, 8pm. Have a flutter on the horses.\nSun 8 Nov · Bingo, eyes down 8pm\nSat 14 Nov · Grooveshack singing group, 8pm. Tickets £5 members, £8 guests.\nSat 21 Nov · Hoy Bingo, 8pm\nSun 22 Nov · Bingo, eyes down 8pm\nSat 28 Nov · Live music from Abi Nash, 8pm\n\nTap Going or Interested on What’s On so your friends can see you’ll be there."}, {"h": "Christmas at the club", "img": "img/slide-party-800.webp", "body": "Sat 5 Dec · Christmas Karaoke. Christmas jumpers welcome!\nSun 13 Dec · Kids Christmas Party, 12pm to 4pm, with games, party food and a visit from Santa.\nThu 31 Dec · New Year’s Eve Party, 7pm to 1am. Ticket only: £10 members, £15 guests. Reserve yours in the app.\n\nFestive opening\nChristmas Day: 12pm to 2pm\nBoxing Day: 10am to 4pm, with a disco 12pm to 4pm\nNew Year’s Day: 12pm to 2pm"}, {"h": "Darts and pool leagues", "img": "img/slide-pool-800.webp", "body": "Our teams are in full swing:\nTuesday · Ladies Darts League\nWednesday · Darts League\nThursday · Pool League\nFriday · Ashford Darts League\n\nHome matches start at 8pm in the Lounge Bar. Come along and cheer them on. The leagues break for Christmas from 21 December.\n\nFancy playing? New players are always welcome. Ask at the bar."}, {"h": "Book your Christmas do", "img": "img/slide-hall1-800.webp", "body": "The Function Room holds up to 120 guests, with a stage, dance floor and its own bar. The Lounge Bar suits smaller parties of up to 60.\n\nDecember evenings are filling up fast. Book in the app under Book, and pay your £100 deposit within 7 days to keep your date."}, {"h": "Meet the bar team", "img": "img/slide-hall2-800.webp", "body": "Say hello to the team behind the bar: Adam, Luis, Yannika and Heather, with Joe, Jamie and Larry helping out through the week. Sam Ashman is our Bar Manager.\n\nGot a suggestion for the club? Message the club from the app. We’d love to hear from you."}]'::jsonb, now());

-- Check
select id, title, issue_date, jsonb_array_length(sections) as sections, published_at is not null as published from public.newsletters order by issue_date desc;
