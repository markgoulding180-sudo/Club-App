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
